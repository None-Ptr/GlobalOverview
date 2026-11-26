import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:global_overview/v4/widgets/v4_bottom_nav.dart';

void main() {
  testWidgets('底部导航展示四项并回传点击索引', (tester) async {
    int? tapped;
    await tester.pumpWidget(
      MaterialApp(
        theme: V4Theme.light(),
        home: Scaffold(
          bottomNavigationBar: V4BottomNav(
            currentIndex: 0,
            onTap: (index) => tapped = index,
          ),
        ),
      ),
    );

    expect(find.text('今日'), findsOneWidget);
    expect(find.text('阅读'), findsOneWidget);
    expect(find.text('学习'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    await tester.tap(find.text('学习'));
    expect(tapped, 2);
  });
}
