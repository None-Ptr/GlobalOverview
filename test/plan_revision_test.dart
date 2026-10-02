import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/screens/plan_screen.dart';
import 'package:global_overview/services/db_service.dart';

/// 统计「计划相关查询」次数，不触碰 sqflite。
class CountingDb extends DbService {
  int planQueries = 0;

  @override
  Future<List<Map<String, dynamic>>> select(String sql, [List<Object?>? params]) async {
    if (sql.contains('FROM plan_items')) planQueries++;
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
  testWidgets('计划变更信号会让常驻的计划页重新加载', (tester) async {
    final db = CountingDb();

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: const MaterialApp(home: PlanScreen()),
    ));
    await tester.pumpAndSettle();

    final before = db.planQueries;
    expect(before, greaterThan(0), reason: '首次进入应已查询计划');

    // 模拟「阅读页/文章页加入计划」触发信号
    final container = ProviderScope.containerOf(tester.element(find.byType(PlanScreen)));
    container.read(planRevisionProvider.notifier).bump();
    await tester.pumpAndSettle();

    expect(db.planQueries, greaterThan(before), reason: '收到变更信号后计划页应重新查询，否则新加入的文章不显示');
  });
}
