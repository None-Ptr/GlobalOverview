import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/services/ai_cost_gate.dart';
import 'package:global_overview/v4/services/ai_cost_service.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';

const _estimate = AiCostEstimate(
  model: 'deepseek-chat',
  inputTokens: 100,
  outputMin: 10,
  outputMax: 20,
);

void main() {
  test('没有可用的 Navigator 时直接放行，方便后台任务与单元测试', () async {
    expect(await AiCostGate.confirm(_estimate), isTrue);
  });

  testWidgets('挂上 Navigator 后弹出成本确认，取消即不调用模型', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: AiCostGate.navigatorKey,
        theme: V4Theme.light(),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );

    final pending = AiCostGate.confirm(_estimate);
    await tester.pumpAndSettle();
    expect(find.text('生成前确认'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await pending, isFalse);
  });
}
