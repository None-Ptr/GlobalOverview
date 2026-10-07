import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/screens/home_screen.dart';
import 'package:global_overview/services/db_service.dart';

/// 只回 kv 的假库，用于把 HabitState 摆成指定样子（真实 HabitService 驱动）。
class _KvDb extends DbService {
  final Map<String, String> kv;
  _KvDb(this.kv);
  @override
  Future<List<Map<String, dynamic>>> select(String sql, [List<Object?>? params]) async {
    if (sql.contains('FROM kv') && params != null && params.isNotEmpty) {
      final v = kv[params.first];
      return v == null ? [] : [<String, dynamic>{'value': v}];
    }
    return [];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {}
  @override
  Future<void> clearCache() async {}
  @override
  Future<void> clearAll() async {}
}

/// 首页有常驻动画（旋转地球 / 呼吸光），pumpAndSettle 永不静止，用确定性 pump。
Future<void> _pump(WidgetTester tester, Map<String, String> kv, {double scale = 1.0}) async {
  tester.view.physicalSize = const Size(420, 1900);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(ProviderScope(
    overrides: [dbProvider.overrideWithValue(_KvDb(kv))],
    child: const MaterialApp(home: HomeScreen()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pump(const Duration(milliseconds: 950));
}

// 全部锁定：streak 5 + total 4 + accuracy 2 + perfect 2 + over 2 = 15
const _allLocked = <String, String>{};
// 解锁 4 个（bronze/silver 各两个）
const _partial = <String, String>{
  'habit_total': '12',
  'habit_totalq': '40',
  'habit_correct': '38',
  'habit_maxstreak': '8',
  'habit_perfect': '1',
  'habit_over': '2',
  'habit_goal': '1',
  'habit_days': '{}',
  'habit_badges': '["v10","s3","s7","a90"]',
};

void main() {
  testWidgets('系统大字号下首页不溢出（固定高网格回归）', (tester) async {
    await _pump(tester, _partial, scale: 2.0);
    expect(tester.takeException(), isNull, reason: '固定 childAspectRatio 的网格在大字号下会 RenderFlex overflow');
  });

  testWidgets('徽章格：未解锁保留类别图标并叠加锁标记', (tester) async {
    await _pump(tester, _allLocked);
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(15));
    // 累计测验 4 枚 + 分组标题 1 + 今日任务里“测验”那行 = 6 个 quiz 图标
    expect(find.byIcon(Icons.quiz_outlined), findsNWidgets(6));
    // 5 枚连续打卡徽章 + 分组标题 + hero 里的火苗 = 7
    expect(find.byIcon(Icons.local_fire_department_outlined), findsNWidgets(7));
  });

  testWidgets('徽章格：已解锁不再显示锁', (tester) async {
    await _pump(tester, _partial);
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(11));
  });
}
