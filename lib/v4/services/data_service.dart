import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/v4/services/backup_io.dart'
    if (dart.library.html) 'package:global_overview/v4/services/backup_io_web.dart';
import 'package:global_overview/v4/services/migration_service.dart';
import 'package:global_overview/v4/services/onboarding_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class V4DataSummary {
  final int vocabWords;
  final int vocabOccurrences;
  final int questionSets;
  final int questions;
  final int answers;
  final int wrongAnswers;
  final int cacheBytes;

  const V4DataSummary({
    this.vocabWords = 0,
    this.vocabOccurrences = 0,
    this.questionSets = 0,
    this.questions = 0,
    this.answers = 0,
    this.wrongAnswers = 0,
    this.cacheBytes = 0,
  });

  bool get hasLearningData =>
      vocabWords > 0 || questionSets > 0 || questions > 0 || answers > 0;

  String get cacheLabel {
    if (cacheBytes <= 0) return '0 KB';
    if (cacheBytes < 1024 * 1024) {
      return (cacheBytes / 1024).ceil().toString() + ' KB';
    }
    return (cacheBytes / (1024 * 1024)).toStringAsFixed(1) + ' MB';
  }
}

class V4BackupInfo {
  final String path;
  final int bytes;
  final DateTime? modified;

  const V4BackupInfo({required this.path, this.bytes = 0, this.modified});

  String get sizeLabel {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024 * 1024) {
      return (bytes / 1024).ceil().toString() + ' KB';
    }
    return (bytes / (1024 * 1024)).toStringAsFixed(1) + ' MB';
  }
}

/// What a restore actually put back, so the screen can say it in numbers.
class V4ImportResult {
  final int rows;
  final int tables;
  final bool profile;

  const V4ImportResult({this.rows = 0, this.tables = 0, this.profile = false});
}

class V4DataService {
  final DbService _db;
  V4DataService(this._db);

  static const learningTables = [
    'vocab_head',
    'vocab_occ',
    'vocab_sentence',
    'question_sets',
    'questions',
    'answers',
    'plan_items',
    'presets',
    'kv',
  ];

  /// Backup key → table. The keys are the ones [exportLearningData] writes, so
  /// an old file still lands in the right table.
  static const _backupTables = <String, String>{
    'vocabHead': 'vocab_head',
    'vocabOccurrences': 'vocab_occ',
    'vocabSentences': 'vocab_sentence',
    'questionSets': 'question_sets',
    'questions': 'questions',
    'answers': 'answers',
    'planItems': 'plan_items',
    'presets': 'presets',
    'settings': 'kv',
  };

  Future<V4DataSummary> summary() async {
    Future<int> count(String sql) async {
      final rows = await _db.select(sql);
      return rows.isEmpty ? 0 : ((rows.first['c'] as num?)?.toInt() ?? 0);
    }

    return V4DataSummary(
      vocabWords: await count('SELECT COUNT(*) AS c FROM vocab_head'),
      vocabOccurrences: await count('SELECT COUNT(*) AS c FROM vocab_occ'),
      questionSets: await count('SELECT COUNT(*) AS c FROM question_sets'),
      questions: await count('SELECT COUNT(*) AS c FROM questions'),
      answers: await count('SELECT COUNT(*) AS c FROM answers'),
      wrongAnswers: await count(
        'SELECT COUNT(DISTINCT questionId) AS c FROM answers WHERE wrong = 1',
      ),
      cacheBytes: await count(
        'SELECT (SELECT COALESCE(SUM(COALESCE(LENGTH(CAST(html AS BLOB)),0) + '
        'COALESCE(LENGTH(CAST(plainText AS BLOB)),0) + '
        'COALESCE(LENGTH(CAST(blocks AS BLOB)),0)),0) FROM articles) + '
        '(SELECT COALESCE(SUM(LENGTH(CAST(result AS BLOB))),0) FROM word_cache) AS c',
      ),
    );
  }

  /// 只清文章正文与词条缓存；阅读列表、精读单和题集记录保留。
  Future<void> clearArticleCache() async {
    await _db.execute(
      'UPDATE articles SET html = NULL, plainText = NULL, blocks = NULL, '
      'curated_blocks = NULL',
    );
    await _db.execute('DELETE FROM word_cache');
  }

  Future<void> clearLearningData() async {
    await _db.deleteTables(learningTables);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(OnboardingService.key);
  }

  Future<Map<String, dynamic>> exportLearningData() async {
    Future<List<Map<String, dynamic>>> rows(String table) =>
        _db.select('SELECT * FROM $table');

    final profile = await OnboardingService().load();
    return {
      'exportedAt': DateTime.now().toIso8601String(),
      'profile': profile?.toJson(),
      'vocabHead': await rows('vocab_head'),
      'vocabOccurrences': await rows('vocab_occ'),
      'vocabSentences': await rows('vocab_sentence'),
      'questionSets': await rows('question_sets'),
      'questions': await rows('questions'),
      'answers': await rows('answers'),
      'planItems': await rows('plan_items'),
      'presets': await rows('presets'),
      'settings': await rows('kv'),
    };
  }

  /// The backup as text: indented so it stays readable and diffable.
  Future<String> exportJson() async {
    final data = await exportLearningData();
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Writes the backup on a device, downloads it in a browser. The path comes
  /// back on a device so the caller can open or share the file; the browser
  /// owns the download, so it returns null there.
  Future<String?> saveBackup() async => saveBackupText(await exportJson());

  /// The backup this app last wrote, or null when there is none.
  Future<String?> readBackup() => readBackupText();

  /// Restores a backup over the current learning records.
  ///
  /// A restore, not a merge: every table the file carries is emptied first, in
  /// one transaction, so a half-applied file cannot leave the reader with two
  /// sets of answers. Rows keep their own ids, which is what holds questions
  /// and answers together. Unknown columns are dropped, so a backup written by
  /// a later version still lands in this one.
  Future<V4ImportResult> importBackup(String raw) async {
    final Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('not an object');
      data = decoded.map((k, v) => MapEntry('$k', v));
    } catch (_) {
      throw const AppException('backupInvalid', '这个文件不是学习数据备份');
    }

    final carried = <String, List<Map<String, dynamic>>>{};
    for (final entry in _backupTables.entries) {
      final value = data[entry.key];
      if (value is! List) continue;
      final rows = value
          .whereType<Map>()
          .map((row) => row.map((k, v) => MapEntry('$k', v)))
          .toList();
      if (rows.isNotEmpty) carried[entry.value] = rows;
    }
    if (carried.isEmpty) {
      throw const AppException('backupEmpty', '备份里没有学习记录');
    }

    final statements = <({String sql, List<Object?> params})>[];
    var restored = 0;
    for (final entry in carried.entries) {
      final table = entry.key;
      final columns = (await _db.select('PRAGMA table_info($table)'))
          .map((row) => '${row['name']}')
          .toSet();
      if (columns.isEmpty) continue;
      statements.add((sql: 'DELETE FROM $table', params: const []));
      for (final row in entry.value) {
        final keys = row.keys.where(columns.contains).toList();
        if (keys.isEmpty) continue;
        final marks = List.filled(keys.length, '?').join(',');
        statements.add((
          sql: 'INSERT OR REPLACE INTO $table (${keys.join(',')}) VALUES ($marks)',
          params: [for (final key in keys) row[key]],
        ));
        restored++;
      }
    }
    await _db.batch(statements);

    var profile = false;
    final rawProfile = data['profile'];
    if (rawProfile is Map) {
      try {
        await OnboardingService().save(
          V4Profile.fromJson(rawProfile.map((k, v) => MapEntry('$k', v))),
        );
        profile = true;
      } catch (_) {
        profile = false;
      }
    }
    return V4ImportResult(
      rows: restored,
      tables: carried.length,
      profile: profile,
    );
  }

  Future<V4BackupInfo?> backupInfo() async {
    if (kIsWeb) return null;
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(V4MigrationService.backupKey);
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final stat = await file.stat();
    return V4BackupInfo(path: path, bytes: stat.size, modified: stat.modified);
  }

  Future<void> deleteBackup() async {
    final info = await backupInfo();
    if (info != null) {
      final file = File(info.path);
      if (await file.exists()) await file.delete();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(V4MigrationService.backupKey);
  }
}