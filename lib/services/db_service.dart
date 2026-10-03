import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

class DbService {
  static const _dbName = 'global_overview.db';

  DbService();

  Database? _db;
  final Completer<Database> _initCompleter = Completer<Database>();
  bool _initStarted = false;
  Future<void> _writeChain = Future.value();

  static String sqlVal(dynamic v) {
    if (v == null) return 'NULL';
    if (v is num) return v.isFinite ? v.toString() : 'NULL';
    if (v is bool) return v ? '1' : '0';
    final nul = String.fromCharCode(0);
    final cleaned = v.toString().replaceAll(nul, '').replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
    return "'${cleaned.replaceAll("'", "''")}'";
  }

  Future<Database> get database {
    if (_db != null) return Future.value(_db!);
    if (!_initStarted) {
      _initStarted = true;
      _open().then(_initCompleter.complete).catchError(_initCompleter.completeError);
    }
    return _initCompleter.future;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = '$dir/$_dbName';
    Future<void> runScript(Database db, String script) async {
      for (final stmt in script.split(';')) {
        final s = stmt.trim();
        if (s.isNotEmpty) await db.execute(s);
      }
    }

    final db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        // 全新安装：建表 + 建全部索引（索引不能只放 onUpgrade，否则新安装会完全没有索引）。
        await runScript(db, _schema);
        await runScript(db, _indexes);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // 老库升级：索引用 CREATE INDEX IF NOT EXISTS，幂等；按当前版本把缺失索引补齐即可。
        if (oldVersion < _dbVersion) await runScript(db, _indexes);
      },
    );
    _db = db;
    return db;
  }

  Future<void> execute(String sql, [List<Object?>? params]) async {
    final db = await database;
    await db.execute(sql, params);
  }

  Future<List<Map<String, dynamic>>> select(String sql, [List<Object?>? params]) async {
    final db = await database;
    return db.rawQuery(sql, params);
  }

  Future<int> insertReturnId(String sql, [List<Object?>? params]) async {
    final db = await database;
    final id = await db.rawInsert(sql, params);
    return id;
  }

  Future<T> _withWriteLock<T>(Future<T> Function() fn) {
    final c = Completer<T>();
    _writeChain = _writeChain.then((_) async {
      try {
        c.complete(await fn());
      } catch (e, s) {
        c.completeError(e, s);
      }
    });
    return c.future;
  }

  Future<void> clearAll() async {
    await _withWriteLock(() async {
      for (final t in ['feeds', 'feed_items', 'articles', 'question_sets', 'questions', 'answers', 'word_cache', 'presets', 'plan_items', 'vocab_head', 'vocab_occ', 'vocab_sentence']) {
        await execute('DELETE FROM $t');
      }
    });
  }

  Future<void> clearCache() async {
    await _withWriteLock(() async {
      for (final t in ['feed_items', 'word_cache']) {
        await execute('DELETE FROM $t');
      }
    });
  }

  Future<Map<int, String>> loadDrafts(List<int> ids) async {
    final out = <int, String>{};
    if (ids.isEmpty) return out;
    final rows = await select(
        'SELECT id, questionId, draft FROM answers WHERE questionId IN (${ids.map((_) => '?').join(',')}) AND gradedAt = 0 AND draft IS NOT NULL',
        ids);
    final best = <int, Map<String, dynamic>>{};
    for (final r in rows) {
      final qid = r['questionId'] as int;
      if (!best.containsKey(qid) || (r['id'] as int) > (best[qid]!['id'] as int)) best[qid] = r;
    }
    for (final qid in ids) {
      out[qid] = best[qid] != null ? (best[qid]!['draft'] as String? ?? '') : '';
    }
    return out;
  }

  Future<void> saveDraft(int questionId, String content) async {
    await _withWriteLock(() async {
      final rows = await select(
          'SELECT id FROM answers WHERE questionId = ? AND gradedAt = 0 AND (final IS NULL OR final = "") ORDER BY id DESC LIMIT 1',
          [questionId]);
      if (rows.isNotEmpty) {
        await execute('UPDATE answers SET draft = ? WHERE id = ?', [content, rows.first['id']]);
      } else {
        await execute('INSERT INTO answers (questionId, draft, gradedAt) VALUES (?, ?, 0)', [questionId, content]);
      }
    });
  }

  Future<void> clearDrafts(List<int> questionIds) async {
    if (questionIds.isEmpty) return;
    await _withWriteLock(() async {
      final ph = questionIds.map((_) => '?').join(',');
      await execute('DELETE FROM answers WHERE questionId IN ($ph) AND gradedAt = 0', questionIds);
    });
  }

  Future<Map<int, List<Map<String, dynamic>>>> loadHistory(List<int> questionIds) async {
    final out = <int, List<Map<String, dynamic>>>{};
    for (final q in questionIds) {
      out[q] = [];
    }
    if (questionIds.isEmpty) return out;
    final rows = await select(
        'SELECT questionId, final, correct, wrong, comment, status, gradedAt FROM answers WHERE questionId IN (${questionIds.map((_) => '?').join(',')}) AND gradedAt > 0 ORDER BY gradedAt ASC',
        questionIds);
    for (final r in rows) {
      final qid = r['questionId'] as int;
      (out[qid] ??= []).add(r);
    }
    return out;
  }

  Future<List<dynamic>?> loadCurated(int id) async {
    final rows = await select('SELECT curated_blocks FROM articles WHERE id = ? LIMIT 1', [id]);
    final raw = rows.isEmpty ? null : rows.first['curated_blocks'] as String?;
    if (raw == null || raw.isEmpty) return null;
    try {
      final bs = jsonDecode(raw);
      return bs is List && bs.isNotEmpty ? bs : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> saveCurated(int id, List<dynamic> blocks) async {
    await execute('UPDATE articles SET curated_blocks = ? WHERE id = ?', [jsonEncode(blocks), id]);
    return true;
  }

  Future<bool> clearCurated(int id) async {
    await execute('UPDATE articles SET curated_blocks = NULL WHERE id = ?', [id]);
    return true;
  }
}

const String _schema = '''
CREATE TABLE IF NOT EXISTS feeds (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT, url TEXT UNIQUE, category TEXT, addedAt INTEGER,
  failCount INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS feed_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  feedId INTEGER, guid TEXT, title TEXT, link TEXT,
  preview TEXT, pubDate INTEGER, fetchedAt INTEGER,
  UNIQUE(feedId, guid)
);
CREATE TABLE IF NOT EXISTS articles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  guid TEXT UNIQUE, title TEXT, author TEXT, sourceUrl TEXT,
  html TEXT, plainText TEXT, blocks TEXT, wordCount INTEGER, capturedAt INTEGER,
  curated_blocks TEXT
);
CREATE TABLE IF NOT EXISTS question_sets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  articleId INTEGER, presetId INTEGER, title TEXT, createdAt INTEGER
);
CREATE TABLE IF NOT EXISTS questions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  setId INTEGER, type TEXT, gradeMode TEXT, prompt TEXT,
  options TEXT, answers TEXT, analysis TEXT, sourceQuote TEXT, createdAt INTEGER
);
CREATE TABLE IF NOT EXISTS answers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  questionId INTEGER NOT NULL,
  draft TEXT,
  final TEXT,
  correct INTEGER,
  wrong INTEGER DEFAULT 0,
  status TEXT DEFAULT 'graded',
  comment TEXT,
  gradedAt INTEGER
);
CREATE TABLE IF NOT EXISTS word_cache (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  word TEXT, mode TEXT, result TEXT, at INTEGER, lemma TEXT,
  UNIQUE(word, mode)
);
CREATE TABLE IF NOT EXISTS vocab_head (
  head TEXT PRIMARY KEY,
  kind TEXT DEFAULT 'word',
  firstSeen INTEGER, lastSeen INTEGER,
  occCount INTEGER DEFAULT 1,
  family TEXT,
  fsrs_state INTEGER DEFAULT 0,
  fsrs_due INTEGER,
  fsrs_s REAL DEFAULT 0,
  fsrs_d REAL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS vocab_occ (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  word TEXT, lemma TEXT,
  articleGuid TEXT, articleTitle TEXT, sourceLabel TEXT,
  sentence TEXT, paraIndex INTEGER, tokIndex INTEGER, at INTEGER,
  UNIQUE(word, articleGuid, paraIndex, tokIndex)
);
CREATE TABLE IF NOT EXISTS vocab_sentence (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sentence TEXT UNIQUE,
  articleGuid TEXT, articleTitle TEXT, sourceLabel TEXT,
  paraIndex INTEGER, tokIndex INTEGER, at INTEGER,
  analysis TEXT
);
CREATE TABLE IF NOT EXISTS presets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT, config TEXT
);
CREATE TABLE IF NOT EXISTS plan_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  articleId INTEGER UNIQUE, addedAt INTEGER, status TEXT DEFAULT 'pending'
);
CREATE TABLE IF NOT EXISTS kv (
  key TEXT PRIMARY KEY,
  value TEXT
);
CREATE TABLE IF NOT EXISTS templates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT UNIQUE, source TEXT
);
''';

/// 追加的索引：只覆盖确实走全表扫描的热路径（执行计划实测：去掉了全表扫描 + 临时 B 树排序）。
/// - feed_items(feedId, pubDate)：单源阅读视图 `WHERE feedId = ? ORDER BY pubDate DESC`，
///   原来走 UNIQUE(feedId,guid) 后再内存排序；合到 (feedId,pubDate) 后直接有序返回。
/// - feed_items.pubDate：聚合阅读列表 `ORDER BY pubDate DESC LIMIT/OFFSET`（JOIN feeds），每次进页都查。
/// - answers(questionId, gradedAt)：草稿/答题历史按这两列过滤排序。
/// - answers(gradedAt)：错题本 / 导出页 `ORDER BY gradedAt DESC` 扫整张只增不减的 answers。
/// - vocab_occ.lemma：词汇页 `GROUP BY lemma` 与 `WHERE lemma = ?`。
/// - questions.setId：`WHERE setId = ?`。
/// - vocab_head(lastSeen)：词汇列表 `ORDER BY lastSeen DESC`。
/// - vocab_head(fsrs_due)：复习页 `WHERE fsrs_due <= ? ORDER BY fsrs_due ASC`（高频打开）。
/// - word_cache.lemma：`WHERE word = ? OR lemma = ?` 的 OR 优化需要两侧各有索引
///   （点查 `word+mode` 已由 schema 的 UNIQUE(word,mode) 覆盖，无需额外索引）。
@visibleForTesting
const List<String> dbIndexStatements = [
  'CREATE INDEX IF NOT EXISTS idx_feed_items_feed_pubdate ON feed_items(feedId, pubDate)',
  'CREATE INDEX IF NOT EXISTS idx_feed_items_pubdate ON feed_items(pubDate)',
  'CREATE INDEX IF NOT EXISTS idx_answers_question ON answers(questionId, gradedAt)',
  'CREATE INDEX IF NOT EXISTS idx_answers_gradedat ON answers(gradedAt)',
  'CREATE INDEX IF NOT EXISTS idx_vocab_occ_lemma ON vocab_occ(lemma)',
  'CREATE INDEX IF NOT EXISTS idx_questions_set ON questions(setId)',
  'CREATE INDEX IF NOT EXISTS idx_vocab_head_lastseen ON vocab_head(lastSeen)',
  'CREATE INDEX IF NOT EXISTS idx_vocab_head_fsrsdue ON vocab_head(fsrs_due)',
  'CREATE INDEX IF NOT EXISTS idx_word_cache_lemma ON word_cache(lemma)',
];

final String _indexes = '${dbIndexStatements.join(';\n')};';

/// 当前数据库版本；每次改 [schema]/[_indexes] 后 +1 并在 [onUpgrade] 里补迁移。
const int _dbVersion = 3;
