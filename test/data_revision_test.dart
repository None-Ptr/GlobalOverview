import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/screens/plan_screen.dart';
import 'package:global_overview/screens/vocab_screen.dart';
import 'package:global_overview/services/db_service.dart';

/// 统计各表查询次数，不触碰 sqflite。
class CountingDb extends DbService {
  int vocabQueries = 0;
  int kvQueries = 0;

  @override
  Future<List<Map<String, dynamic>>> select(String sql, [List<Object?>? params]) async {
    if (sql.contains('vocab_head') || sql.contains('vocab_occ') || sql.contains('vocab_sentence')) vocabQueries++;
    if (sql.contains('FROM kv')) kvQueries++;
    return [];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {}

  @override
  Future<void> clearCache() async {}

  @override
  Future<void> clearAll() async {}
}

void main() {
  testWidgets('词汇变更信号会让常驻的词汇页重新加载', (tester) async {
    final db = CountingDb();
    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: const MaterialApp(home: VocabScreen()),
    ));
    await tester.pumpAndSettle();

    final before = db.vocabQueries;
    expect(before, greaterThan(0), reason: '首次进入应已查询词汇');

    // 模拟「阅读页点词 / 复习页评分」触发信号
    final container = ProviderScope.containerOf(tester.element(find.byType(VocabScreen)));
    container.read(vocabRevisionProvider.notifier).bump();
    await tester.pump(const Duration(milliseconds: 600)); // 越过防抖
    await tester.pumpAndSettle();

    expect(db.vocabQueries, greaterThan(before), reason: '收到词汇变更后应重新查询，否则新增生词/待复习数不更新');
  });

  testWidgets('全局目标变更信号会让计划页重新读取目标', (tester) async {
    final db = CountingDb();
    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: const MaterialApp(home: PlanScreen()),
    ));
    await tester.pumpAndSettle();

    final before = db.kvQueries;
    expect(before, greaterThan(0), reason: '首次进入应已读取全局目标');

    final container = ProviderScope.containerOf(tester.element(find.byType(PlanScreen)));
    container.read(targetLevelRevisionProvider.notifier).bump();
    await tester.pumpAndSettle();

    expect(db.kvQueries, greaterThan(before), reason: '「我的」页改目标后，计划页应同步新值');
  });
}
