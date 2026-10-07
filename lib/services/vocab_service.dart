import 'dart:convert';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/llm_service.dart';

class VocabService {
  final DbService _db;
  final LlmService _llm;
  VocabService(this._db, this._llm);

  String lemmaOf(String word) => word.toLowerCase().trim();

  Future<void> recordOccurrence(String word, String sentence, String articleGuid, String articleTitle, String sourceLabel, int paraIndex, int tokIndex) async {
    final lemma = lemmaOf(word);
    final now = DateTime.now().millisecondsSinceEpoch;
    // 同一处同一词只记一次：用 INSERT OR IGNORE + 返回 id 判定（命中 UNIQUE 时 rawInsert 返回 0），
    // 省掉一次存在性 SELECT；避免重复点词把 occCount 刷高。点词是很热的写路径，每少一次往返都划算。
    final id = await _db.insertReturnId(
        'INSERT OR IGNORE INTO vocab_occ (word, lemma, articleGuid, articleTitle, sourceLabel, sentence, paraIndex, tokIndex, at) VALUES (?,?,?,?,?,?,?,?,?)',
        [word, lemma, articleGuid, articleTitle, sourceLabel, sentence, paraIndex, tokIndex, now]);
    if (id == 0) return; // 该位置已记录过
    final rows = await _db.select('SELECT head FROM vocab_head WHERE head = ?', [lemma]);
    if (rows.isEmpty) {
      await _db.execute(
          'INSERT INTO vocab_head (head, kind, firstSeen, lastSeen, occCount, fsrs_state, fsrs_due, fsrs_s, fsrs_d) VALUES (?,?,?,?,?,?,?,?,?)',
          [lemma, 'word', now, now, 1, 0, now, 0.0, 0.0]);
    } else {
      await _db.execute('UPDATE vocab_head SET occCount = occCount + 1, lastSeen = ? WHERE head = ?', [now, lemma]);
    }
  }

  // ================= 词汇中心（对齐 vocab.js） =================

  static const _legacySpreadDays = 30;

  /// 把历史 word_cache 词同步进 vocab_head（幂等），旧生词按查词时间分 30 天错峰到期。
  Future<void> syncHeadsFromCache() async {
    final allHeads = await _db.select('SELECT head FROM vocab_head');
    for (final h in allHeads) {
      final hd = '${h['head']}';
      final spaces = hd.length - hd.replaceAll(' ', '').length;
      if (hd.length > 80 || spaces > 5) {
        await _db.execute('DELETE FROM vocab_head WHERE head = ?', [hd]);
      }
    }
    final rows = await _db.select("SELECT word, lemma, at FROM word_cache WHERE word IS NOT NULL AND mode IN ('en2zh','en2en')");
    final clean = rows.where((r) {
      final w = '${r['word']}';
      return w.length <= 80 && (w.length - w.replaceAll(' ', '').length) <= 5;
    }).toList();
    if (clean.isEmpty) return;
    final existing = await _db.select('SELECT head FROM vocab_head');
    final have = existing.map((e) => '${e['head']}').toSet();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final r in clean) {
      final head = ((r['lemma'] as String?)?.isNotEmpty == true ? r['lemma'] as String : '${r['word']}'.toLowerCase());
      if (head.isEmpty || have.contains(head)) continue;
      have.add(head);
      final at = (r['at'] as int?) ?? now;
      final days = ((at ~/ 86400000).abs()) % _legacySpreadDays;
      final due = now + days * 86400000;
      await _db.execute(
          'INSERT OR IGNORE INTO vocab_head (head, kind, firstSeen, lastSeen, occCount, fsrs_state, fsrs_due, fsrs_s, fsrs_d) VALUES (?,?,?,?,?,?,?,?,?)',
          [head, 'word', at, at, 1, 0, due, 1.0, 5.0]);
    }
  }

  /// 批量读取 word_cache / 其它大字段时的单批上限（规避 Android CursorWindow）。
  static const _chunk = 100;

  /// 词汇列表（附带 sourceCount / latestSentence / zh）。
  Future<List<Map<String, dynamic>>> getHeads() async {
    final list = (await _db.select('SELECT head, kind, firstSeen, lastSeen, occCount, family, fsrs_state, fsrs_due FROM vocab_head ORDER BY lastSeen DESC'))
        .map((e) => Map<String, dynamic>.of(e))
        .toList();
    // vocab_occ 会随阅读持续增长，整表拉取会逼近 CursorWindow；这里只要两个聚合量，
    // 结果行数由「词条数」决定而不是「出现次数」。
    // 注：SQLite 在聚合查询里对裸列（sentence）的取值来自 max(at) 命中的那一行，这是
    // SQLite 的既定行为（本 App 只跑 Android/sqflite）。
    final aggRows = await _db.select('SELECT lemma, COUNT(DISTINCT articleGuid) AS c, MAX(at) AS m, sentence FROM vocab_occ GROUP BY lemma');
    final sourceCount = <String, int>{};
    final latestSentence = <String, String>{};
    for (final r in aggRows) {
      final k = '${r['lemma']}';
      sourceCount[k] = (r['c'] as int?) ?? 0;
      latestSentence[k] = (r['sentence'] as String?) ?? '';
    }
    // result 是整段 JSON，一次全表取会逼近 Android CursorWindow 上限，按 100 条分批。
    final heads = list.map((h) => '${h['head']}').toList();
    final wcMap = <String, Map<String, dynamic>>{};
    for (var i = 0; i < heads.length; i += _chunk) {
      final chunk = heads.skip(i).take(_chunk).toList();
      final ph = chunk.map((_) => '?').join(',');
      final rows = await _db.select(
        'SELECT word, lemma, result FROM word_cache WHERE word IN ($ph) OR lemma IN ($ph)',
        [...chunk, ...chunk],
      );
      for (final w in rows) {
        final k = (w['lemma'] as String?)?.isNotEmpty == true ? w['lemma'] as String : '${w['word']}';
        wcMap[k] ??= w;
      }
    }
    for (final h in list) {
      final head = '${h['head']}';
      h['sourceCount'] = sourceCount[head] ?? 0;
      h['latestSentence'] = latestSentence[head] ?? '';
      final hit = wcMap[head];
      if (hit != null && hit['result'] != null) {
        try {
          final r = jsonDecode(hit['result'] as String);
          if (r is Map) {
            if (r['kind'] == 'dict') {
              final senses = r['senses'] as List?;
              h['zh'] = (senses != null && senses.isNotEmpty && senses.first is Map) ? (senses.first['definition'] ?? '') : '';
            } else if (r['text'] != null) {
              h['zh'] = r['text'];
            }
          }
        } catch (_) {}
      }
    }
    return list;
  }

  Future<List<Map<String, dynamic>>> getOccurrence(String head) async {
    final h = lemmaOf(head);
    return (await _db.select(
            'SELECT articleGuid, articleTitle, sourceLabel, sentence, paraIndex, tokIndex, at FROM vocab_occ WHERE lemma = ? ORDER BY at DESC', [h]))
        .map((e) => Map<String, dynamic>.of(e))
        .toList();
  }

  /// 页面要显示具体数字，且 fsrs_due 有索引，走的是索引内计数。
  Future<int> dueCount() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await _db.select('SELECT COUNT(*) AS n FROM vocab_head WHERE fsrs_due <= ?', [now]);
    return (rows.isEmpty ? 0 : (rows.first['n'] as int? ?? 0));
  }

  /// 句子表只用于「最近句子」展示，排序后截断即可。
  static const _sentenceLimit = 200;

  Future<List<Map<String, dynamic>>> getSentences() async {
    return (await _db.select('SELECT sentence, articleGuid, articleTitle, sourceLabel, paraIndex, tokIndex, at, analysis FROM vocab_sentence ORDER BY at DESC LIMIT $_sentenceLimit'))
        .map((e) => Map<String, dynamic>.of(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getDueCards(int limit) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.select('SELECT head, fsrs_state, fsrs_due, fsrs_s, fsrs_d FROM vocab_head WHERE fsrs_due <= ? ORDER BY fsrs_due ASC LIMIT ?', [now, limit]);
  }

  /// FSRS 简化内核：以稳定性 S(天) + 难度 D(1..10) 驱动间隔。grade: 1忘了 2模糊 3记得 4轻松。
  Future<void> scheduleReview(String head, int grade) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await _db.select('SELECT fsrs_s, fsrs_d, fsrs_state FROM vocab_head WHERE head = ?', [head]);
    if (rows.isEmpty) return;
    var s = (rows.first['fsrs_s'] as num?)?.toDouble() ?? 1.0;
    var d = (rows.first['fsrs_d'] as num?)?.toDouble() ?? 5.0;
    switch (grade) {
      case 1:
        s = 1.0;
        d = (d + 1).clamp(1, 10).toDouble();
        break;
      case 2:
        s = s * 1.2;
        d = (d + 0.5).clamp(1, 10).toDouble();
        break;
      case 3:
        s = s * 2.3;
        break;
      case 4:
        s = s * 3.0;
        d = (d - 0.5).clamp(1, 10).toDouble();
        break;
    }
    final due = now + s.round() * 86400000;
    // 首刷判定：vocab_head.fsrs_s 永远是数字（建表 DEFAULT 0 + 写入时给值），
    // 不能用它判「是否首次复习」；正确依据是 fsrs_state==0（新词尚未评级）。
    final curState = (rows.first['fsrs_state'] as int?) ?? 0;
    final state = (grade >= 3) ? (curState == 0 ? 1 : 2) : 0;
    await _db.execute('UPDATE vocab_head SET fsrs_state = ?, fsrs_due = ?, fsrs_s = ?, fsrs_d = ?, lastSeen = ? WHERE head = ?',
        [state, due, s, d, now, head]);
  }

  Future<void> removeHead(String head) async {
    await _db.execute('DELETE FROM vocab_head WHERE head = ?', [head]);
    await _db.execute('DELETE FROM vocab_occ WHERE lemma = ?', [head]);
  }

  Future<void> clearVocab() async {
    await _db.execute('DELETE FROM vocab_head');
    await _db.execute('DELETE FROM vocab_occ');
    await _db.execute('DELETE FROM word_cache');
  }

  /// 收藏一句句子（来自文章页取句/选区）。已存在则忽略（按 sentence 唯一）。
  Future<bool> saveSentence(String sentence, String articleGuid, String articleTitle, String sourceLabel, int paraIndex, int tokIndex) async {
    final s = sentence.trim();
    if (s.isEmpty) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.execute(
      'INSERT OR IGNORE INTO vocab_sentence (sentence, articleGuid, articleTitle, sourceLabel, paraIndex, tokIndex, at) VALUES (?,?,?,?,?,?,?)',
      [s, articleGuid, articleTitle, sourceLabel, paraIndex, tokIndex, now],
    );
    return true;
  }

  /// 对收藏句子做语法/语块拆解。结果 upsert 进 vocab_sentence（先 INSERT 保底新句、再 UPDATE 覆盖已有句的 analysis，
  /// 不破坏 saveSentence 写入的 articleGuid 等元数据）。
  Future<Map<String, dynamic>> analyzeSentence(String sentence) async {
    const sys = '你是英语语法与语块分析助手。只输出对象，不要解释、不要 markdown。结构：'
        '{"translation":"整句自然中文翻译",'
        '"chunks":[{"text":"语块原文","type":"phrase|clause|idiom|fixed","note":"这个语块的意思/作用"}],'
        '"grammar":[{"point":"语法点","explain":"一句话说明"}],'
        '"keywords":[{"word":"重点词","pos":"词性","zh":"中文释义"}]}';
    final res = await _llm.structured(sys, '请拆解并分析这句话：\n$sentence', temperature: 0.3);
    final data = <String, dynamic>{
      'translation': res is Map ? (res['translation'] ?? '') : '',
      'chunks': (res is Map && res['chunks'] is List) ? res['chunks'] : [],
      'grammar': (res is Map && res['grammar'] is List) ? res['grammar'] : [],
      'keywords': (res is Map && res['keywords'] is List) ? res['keywords'] : [],
    };
    final now = DateTime.now().millisecondsSinceEpoch;
    final enc = jsonEncode(data);
    await _db.execute('INSERT OR IGNORE INTO vocab_sentence (sentence, analysis, at) VALUES (?,?,?)', [sentence, enc, now]);
    await _db.execute('UPDATE vocab_sentence SET analysis = ? WHERE sentence = ?', [enc, sentence]);
    return data;
  }

  /// AI 整理：把查询过的生词按主题聚类分组。
  Future<Map<String, dynamic>> organize() async {
    final wc = <Map<String, dynamic>>[];
    for (var offset = 0; offset < 500; offset += _chunk) {
      final rows = await _db.select('SELECT word, mode, result FROM word_cache LIMIT $_chunk OFFSET $offset');
      if (rows.isEmpty) break;
      wc.addAll(rows);
      if (rows.length < _chunk) break;
    }
    final list = wc.map((w) {
      var hint = '';
      try {
        if (w['result'] != null) {
          final r = jsonDecode(w['result'] as String);
          if (r is Map) {
            if (r['kind'] == 'dict') {
              hint = '${r['phonetic'] ?? ''} ${(r['senses'] as List? ?? []).map((s) => s['definition']).join('; ')}';
            } else if (r['text'] != null) {
              hint = '${r['text']}'.length > 140 ? '${r['text']}'.substring(0, 140) : '${r['text']}';
            }
          }
        }
      } catch (_) {}
      return {'word': w['word'], 'mode': w['mode'], 'hint': hint};
    }).toList();
    const sys = '你是一个英语词汇整理助手。';
    final prompt = '下面是一批用户在阅读中查询过的生词（JSON 数组，含 word / mode / hint）。'
        '请按主题将生词聚类分组，并为每个词补全：lemma（词族原形小写）、pos（词性缩写）、zh（中文释义）、en（英文释义）、family（常见形态数组，含自身）、example（一个地道英文例句）。'
        '只输出如下 JSON：{"groups":[{"theme":"...","items":[{"word":"...","lemma":"...","pos":"...","zh":"...","en":"...","family":[...],"example":"..."}]}]}\n生词列表：\n${jsonEncode(list)}';
    final res = await _llm.structured(sys, prompt, temperature: 0.3);
    if (res is! Map || res['groups'] is! List) throw Exception('模型返回结构异常');
    return Map<String, dynamic>.from(res);
  }
}
