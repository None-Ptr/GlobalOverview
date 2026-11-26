import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/screens/guide_screen.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:global_overview/v4/widgets/feature_guide_sheet.dart';

Widget _host() => MaterialApp(
      theme: V4Theme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showFeatureGuideSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('新功能说明列出四项并可关闭', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('这几件事，现在可以做'), findsOneWidget);
    expect(find.text('导入文章'), findsOneWidget);
    expect(find.text('自定义 RSS'), findsOneWidget);
    expect(find.text('AI 精选'), findsOneWidget);
    expect(find.text('生成精读练习'), findsOneWidget);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('这几件事，现在可以做'), findsNothing);
  });

  testWidgets('可以从说明直接进入使用指南', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('看使用指南'));
    await tester.pumpAndSettle();

    expect(find.byType(V4GuideScreen), findsOneWidget);
    expect(find.text('使用指南'), findsOneWidget);
  });
}
