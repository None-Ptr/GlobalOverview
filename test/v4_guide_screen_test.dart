import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/screens/guide_screen.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';

void main() {
  testWidgets('使用指南列出四组功能，窄屏大字不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: V4Theme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.6),
          ),
          child: child!,
        ),
        home: const V4GuideScreen(),
      ),
    );
    await tester.pump();

    expect(find.text('阅读'), findsOneWidget);
    expect(find.text('导入文章'), findsOneWidget);
    expect(find.text('AI 精选'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(find.text('本机数据'), 200);
    await tester.pump();

    expect(find.text('AI 与数据'), findsOneWidget);
    expect(find.text('本机数据'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
