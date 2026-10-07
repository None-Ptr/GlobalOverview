import 'package:flutter_test/flutter_test.dart';

import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/llm_service.dart';
import 'package:global_overview/services/quiz_service.dart';

import 'fake_db.dart';

/// 记录所有 SQL 的假库（含 execute）。
class _RecDb extends FakeDb {
  final List<String> log = [];

  @override
  Future<List<Map<String, dynamic>>> select(String sql, [List<Object?>? params]) async {
    log.add(sql);
    return [];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {
    log.add(sql);
  }
}

int _placeholders(String sql) => '?'.allMatches(sql).length;
int _answersQueries(List<String> log) => log.where((q) => q.contains('FROM answers')).length;

void main() {
  test('loadQuestionsByIds 按 sqlBindChunk 切片，单条占位符不超上限', () async {
    final db = _RecDb();
    final svc = QuizService(LlmService(HttpService(), AppConfigService()), db);
    final ids = List<int>.generate(950, (i) => i + 1);

    await svc.loadQuestionsByIds(ids);

    expect(db.log.length, 3, reason: '950 / $sqlBindChunk 应为 3 批');
    for (final q in db.log) {
      expect(_placeholders(q) <= sqlBindChunk, isTrue, reason: q);
      expect(q.contains('SELECT * FROM questions'), isFalse, reason: q);
    }
  });

  test('loadDrafts / loadHistory 的 IN 查询同样分批', () async {
    final db = _RecDb();
    final ids = List<int>.generate(850, (i) => i + 1);

    await db.loadDrafts(ids);
    expect(_answersQueries(db.log), 3, reason: '850 / $sqlBindChunk 应为 3 批');
    for (final q in db.log) {
      expect(_placeholders(q) <= sqlBindChunk, isTrue, reason: q);
    }

    db.log.clear();
    await db.loadHistory(ids);
    expect(_answersQueries(db.log), 3);
  });

  test('clearDrafts 分批删除', () async {
    final db = _RecDb();
    await db.clearDrafts(List<int>.generate(850, (i) => i + 1));
    final dels = db.log.where((q) => q.startsWith('DELETE FROM answers')).toList();
    expect(dels.length, 3);
    for (final q in dels) {
      expect(_placeholders(q) <= sqlBindChunk, isTrue, reason: q);
    }
  });
}
