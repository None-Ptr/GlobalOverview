import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/screens/usage_ledger_screen.dart';
import 'package:global_overview/v4/services/ai_cost_service.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: V4Theme.light(),
          home: const V4UsageLedgerScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('没有记录时显示空状态', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pump(tester);

    expect(find.text('还没有 AI 调用记录'), findsOneWidget);
    expect(find.text('生成练习或判分后，这里会显示本机用量。'), findsOneWidget);
  });

  testWidgets('有记录时显示操作、模型、Token 与金额', (tester) async {
    SharedPreferences.setMockInitialValues({
      AiUsageLedger.key: jsonEncode([
        {
          'operation': '生成练习题',
          'model': 'deepseek-chat',
          'inputTokens': 1200,
          'outputTokens': 480,
          'amount': 0.0123,
          'currency': 'CNY',
        },
        {
          'operation': '判分',
          'model': 'gpt-4o',
          'inputTokens': 300,
          'outputTokens': 90,
        },
      ]),
    });
    await pump(tester);

    expect(find.text('生成练习题'), findsOneWidget);
    expect(find.text('deepseek-chat  输入 1200 / 输出 480'), findsOneWidget);
    expect(find.text('CNY 0.0123'), findsOneWidget);
    expect(find.text('判分'), findsOneWidget);
    expect(find.text('gpt-4o  输入 300 / 输出 90'), findsOneWidget);
    // The second record has no amount, so only one price line exists.
    expect(find.textContaining('CNY'), findsOneWidget);
  });

  testWidgets('记录损坏时按空列表处理，不抛异常', (tester) async {
    SharedPreferences.setMockInitialValues({AiUsageLedger.key: 'not json'});
    await pump(tester);

    expect(find.text('还没有 AI 调用记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
