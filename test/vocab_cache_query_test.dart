import 'package:flutter_test/flutter_test.dart';

import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/llm_service.dart';
import 'package:global_overview/services/vocab_service.dart';

import 'fake_db.dart';

class _Rec extends FakeDb {
  final List<String> log = [];
  static const heads = 120;

  @override
  Future<List<Map<String, dynamic>>> select(String sql, [List<Object?>? params]) async {
    log.add(sql);
    if (sql.contains('FROM vocab_head')) {
      return [
        for (var i = 0; i < heads; i++)
          <String, dynamic>{'head': 'w$i', 'kind': 'word', 'firstSeen': 0, 'lastSeen': 0, 'occCount': 1, 'family': '[]', 'fsrs_state': 0, 'fsrs_due': 0}
      ];
    }
    if (sql.contains('FROM vocab_occ')) return [];
    if (sql.contains('FROM word_cache')) {
      final first = (params ?? []).isNotEmpty ? '${params!.first}' : 'x';
      return [<String, dynamic>{'word': first, 'lemma': first, 'result': '{"kind":"dict"}'}];
    }
    return [];
  }
}

VocabService _svc(_Rec db) => VocabService(db, LlmService(HttpService(), AppConfigService()));

List<String> _cacheSql(_Rec db) => db.log.where((s) => s.contains('FROM word_cache')).toList();

void main() {
  test('getHeads 按批读取 result，不再一次全表拉取', () async {
    final db = _Rec();
    await _svc(db).getHeads();

    final qs = _cacheSql(db);
    expect(qs, isNotEmpty);
    for (final q in qs) {
      expect(q, contains('IN ('), reason: '必须按批次限定，不能无界拉取: $q');
    }
    expect(qs.any((q) => q.trim() == 'SELECT word, lemma, result FROM word_cache'), isFalse);
    expect(qs.length, 2, reason: '120 个词应分成 100 + 20 两批');
  });

  test('getHeads 对 vocab_occ 只做聚合，不再整表拉取', () async {
    final db = _Rec();
    await _svc(db).getHeads();

    final qs = db.log.where((s) => s.contains('FROM vocab_occ')).toList();
    expect(qs, isNotEmpty);
    for (final q in qs) {
      expect(q, contains('GROUP BY'), reason: 'vocab_occ 会持续增长，必须聚合查询: $q');
    }
    expect(qs.any((q) => q.contains('ORDER BY at DESC')), isFalse);
  });

  test('getHeads 只查vocab_occ 一次，来源数与最近句合并在同一次聚合里', () async {
    final db = _Rec();
    await _svc(db).getHeads();

    final qs = db.log.where((s) => s.contains('FROM vocab_occ')).toList();
    expect(qs.length, 1, reason: '两次 GROUP BY 可合并成一次，避免重复全索引扫描: $qs');
    expect(qs.single, contains('COUNT(DISTINCT articleGuid)'));
    expect(qs.single, contains('MAX(at)'));
  });

  test('getSentences 排序后截断，避免无界拉取', () async {
    final db = _Rec();
    await _svc(db).getSentences();

    final qs = db.log.where((s) => s.contains('FROM vocab_sentence')).toList();
    expect(qs.length, 1);
    expect(qs.single, contains('ORDER BY at DESC'));
    expect(qs.single, contains('LIMIT'), reason: '句子表只用于最近句子展示，必须有上限: ${qs.single}');
  });

  test('organize 按批翻页，单批不超过 100 条', () async {
    final db = _Rec();
    try {
      await _svc(db).organize();
    } catch (_) {
      // 只关心 SQL，LLM 调用失败无所谓
    }
    final qs = _cacheSql(db);
    expect(qs, isNotEmpty);
    for (final q in qs) {
      expect(q, contains('LIMIT 100'), reason: '单批必须受限: $q');
    }
  });
}