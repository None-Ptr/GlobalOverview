import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:global_overview/services/db_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class V4MigrationSummary {
  final int vocabWords;
  final int vocabOccurrences;
  final int questionSets;
  final int questions;
  final int answers;
  final int wrongAnswers;

  const V4MigrationSummary({
    this.vocabWords = 0,
    this.vocabOccurrences = 0,
    this.questionSets = 0,
    this.questions = 0,
    this.answers = 0,
    this.wrongAnswers = 0,
  });

  bool get hasLearningData =>
      vocabWords > 0 || questionSets > 0 || questions > 0 || answers > 0;

  Map<String, dynamic> toJson() => {
    'vocabWords': vocabWords,
    'vocabOccurrences': vocabOccurrences,
    'questionSets': questionSets,
    'questions': questions,
    'answers': answers,
    'wrongAnswers': wrongAnswers,
  };

  factory V4MigrationSummary.fromJson(Map<String, dynamic> json) =>
      V4MigrationSummary(
        vocabWords: (json['vocabWords'] as num?)?.toInt() ?? 0,
        vocabOccurrences: (json['vocabOccurrences'] as num?)?.toInt() ?? 0,
        questionSets: (json['questionSets'] as num?)?.toInt() ?? 0,
        questions: (json['questions'] as num?)?.toInt() ?? 0,
        answers: (json['answers'] as num?)?.toInt() ?? 0,
        wrongAnswers: (json['wrongAnswers'] as num?)?.toInt() ?? 0,
      );
}

abstract class V4MigrationStore {
  Future<V4MigrationSummary> inspect();
  Future<bool> isComplete();
  Future<String?> migrate();
}

class V4MigrationService implements V4MigrationStore {
  final DbService _db;
  V4MigrationService(this._db);

  static const completeKey = 'v4_migration_complete';
  static const summaryKey = 'v4_migration_summary';
  static const backupKey = 'v4_migration_backup_path';
  static const _dbFileName = 'global_overview.db';

  @override
  Future<bool> isComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(completeKey) == true;
  }

  Future<bool> shouldPrompt() async {
    // A browser starts empty: there is no V3 install to migrate, and no file
    // system to copy a database backup into.
    if (kIsWeb) return false;
    if (await isComplete()) return false;
    return (await inspect()).hasLearningData;
  }

  @override
  Future<V4MigrationSummary> inspect() async {
    Future<int> count(String sql) async {
      final rows = await _db.select(sql);
      return rows.isEmpty ? 0 : (rows.first['c'] as int? ?? 0);
    }

    return V4MigrationSummary(
      vocabWords: await count('SELECT COUNT(*) AS c FROM vocab_head'),
      vocabOccurrences: await count('SELECT COUNT(*) AS c FROM vocab_occ'),
      questionSets: await count('SELECT COUNT(*) AS c FROM question_sets'),
      questions: await count('SELECT COUNT(*) AS c FROM questions'),
      answers: await count('SELECT COUNT(*) AS c FROM answers'),
      wrongAnswers: await count(
        'SELECT COUNT(DISTINCT questionId) AS c FROM answers WHERE wrong = 1',
      ),
    );
  }

  @override
  Future<String?> migrate() async {
    if (await isComplete()) return null;
    final summary = await inspect();
    final backup = await _backupDatabase();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(summaryKey, jsonEncode(summary.toJson()));
    if (backup != null) await prefs.setString(backupKey, backup);
    await prefs.setBool(completeKey, true);
    return backup;
  }

  /// 先 checkpoint 再复制主库，避免 WAL 中尚未落盘的数据缺失。
  /// 备份失败会抛出，调用方不得继续标记迁移完成。
  Future<String?> _backupDatabase() async {
    if (kIsWeb) return null;
    final db = await _db.database;
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    final dir = await getDatabasesPath();
    final source = File(dir + '/' + _dbFileName);
    if (!await source.exists()) return null;
    final target = File(dir + '/global_overview_v3_backup.db');
    if (await target.exists()) await target.delete();
    await source.copy(target.path);
    return target.path;
  }
}