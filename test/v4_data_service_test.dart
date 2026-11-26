import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/v4/services/data_service.dart';
import 'package:global_overview/v4/services/migration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingDb extends DbService {
  final List<String> executed = [];
  final Map<String, int> counts;
  final Map<String, List<Map<String, dynamic>>> rows;

  _RecordingDb({this.counts = const {}, this.rows = const {}});

  @override
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?>? params,
  ]) async {
    for (final entry in counts.entries) {
      if (sql.contains(entry.key)) {
        return [
          {'c': entry.value},
        ];
      }
    }
    for (final entry in rows.entries) {
      if (sql.contains(entry.key)) return entry.value;
    }
    return [];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {
    executed.add(sql);
  }

  @override
  Future<void> deleteTables(List<String> tables) async {
    for (final table in tables) {
      executed.add('DELETE FROM $table');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('汇总学习数据与缓存体积', () async {
    final db = _RecordingDb(
      counts: {
        'FROM vocab_head': 12,
        'FROM vocab_occ': 30,
        'FROM question_sets': 2,
        'FROM questions': 10,
        'DISTINCT questionId': 3,
        'FROM answers': 8,
        'CAST(html AS BLOB)': 2048,
      },
    );
    final summary = await V4DataService(db).summary();

    expect(summary.vocabWords, 12);
    expect(summary.vocabOccurrences, 30);
    expect(summary.questionSets, 2);
    expect(summary.questions, 10);
    expect(summary.answers, 8);
    expect(summary.wrongAnswers, 3);
    expect(summary.cacheBytes, 2048);
    expect(summary.cacheLabel, '2 KB');
    expect(summary.hasLearningData, isTrue);
  });

  test('清理文章缓存只清正文并保留阅读列表与精读单', () async {
    final db = _RecordingDb();
    await V4DataService(db).clearArticleCache();

    expect(db.executed, contains('DELETE FROM word_cache'));
    expect(
      db.executed.any(
        (sql) => sql.startsWith('UPDATE articles SET') && sql.contains('plainText = NULL'),
      ),
      isTrue,
    );
    expect(db.executed, isNot(contains('DELETE FROM articles')));
    expect(db.executed, isNot(contains('DELETE FROM feed_items')));
    expect(db.executed, isNot(contains('DELETE FROM plan_items')));
    expect(db.executed, isNot(contains('DELETE FROM question_sets')));
  });

  test('清空学习数据删除学习表并移除首启档案', () async {
    final db = _RecordingDb();
    await V4DataService(db).clearLearningData();

    expect(db.executed, contains('DELETE FROM vocab_head'));
    expect(db.executed, contains('DELETE FROM answers'));
    expect(db.executed, contains('DELETE FROM plan_items'));
    expect(db.executed.any((sql) => sql.contains('articles')), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('v4_onboarding_profile'), isNull);
  });

  test('导出学习数据包含学习表与档案', () async {
    final db = _RecordingDb(
      rows: {
        'FROM vocab_head': [
          {'head': 'planet'},
        ],
        'FROM answers': [
          {'id': 1, 'wrong': 1},
        ],
      },
    );
    final data = await V4DataService(db).exportLearningData();

    expect(data['vocabHead'], [
      {'head': 'planet'},
    ]);
    expect(data['answers'], [
      {'id': 1, 'wrong': 1},
    ]);
    expect(data.containsKey('profile'), isTrue);
    expect(data.containsKey('exportedAt'), isTrue);
  });

  test('没有迁移备份时返回空', () async {
    final service = V4DataService(_RecordingDb());
    expect(await service.backupInfo(), isNull);
  });

  test('缓存体积按 KB / MB 分级显示', () async {
    expect(const V4DataSummary().cacheLabel, '0 KB');
    expect(const V4DataSummary(cacheBytes: 1).cacheLabel, '1 KB');
    expect(const V4DataSummary(cacheBytes: 2048).cacheLabel, '2 KB');
    expect(const V4DataSummary(cacheBytes: 3 * 1024 * 1024).cacheLabel, '3.0 MB');
    expect(const V4BackupInfo(path: 'x').sizeLabel, '0 KB');
    expect(const V4BackupInfo(path: 'x', bytes: 5 * 1024 * 1024).sizeLabel, '5.0 MB');
  });

  test('有迁移备份时返回路径、体积与时间，删除后一并清空', () async {
    final dir = await Directory.systemTemp.createTemp('v4_backup');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/global_overview_v3_backup.db');
    await file.writeAsBytes(List<int>.filled(4096, 7));
    SharedPreferences.setMockInitialValues({
      V4MigrationService.backupKey: file.path,
    });

    final service = V4DataService(_RecordingDb());
    final info = await service.backupInfo();

    expect(info, isNotNull);
    expect(info!.path, file.path);
    expect(info.bytes, 4096);
    expect(info.sizeLabel, '4 KB');
    expect(info.modified, isNotNull);

    await service.deleteBackup();
    expect(await file.exists(), isFalse);
    expect(await service.backupInfo(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(V4MigrationService.backupKey), isNull);
  });

  test('备份记录指向的文件已丢失时返回空', () async {
    SharedPreferences.setMockInitialValues({
      V4MigrationService.backupKey: 'D:/nonexistent/global_overview_v3_backup.db',
    });
    expect(await V4DataService(_RecordingDb()).backupInfo(), isNull);
  });
}
