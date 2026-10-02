import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/theme/app_theme.dart';
import 'package:global_overview/widgets/go_globe.dart';
import 'package:global_overview/widgets/go_ui.dart';

void main() {
  // 注意：地球是持续动画，断言期间只能用 pump，不能 pumpAndSettle（永不 settle）。

  testWidgets('GoPage 的 globe/globeActive 透传到地球层，不可见时暂停', (tester) async {
    var active = true;
    late StateSetter setOuter;

    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: StatefulBuilder(
        builder: (c, setState) {
          setOuter = setState;
          return GoPage(
            globe: true,
            globeActive: active,
            child: const SizedBox.expand(),
          );
        },
      ),
    ));
    await tester.pump();

    expect(find.byType(GoGlobe), findsOneWidget);
    expect(tester.widget<GoGlobe>(find.byType(GoGlobe)).active, isTrue, reason: '默认应处于活动（自转）状态');

    setOuter(() => active = false);
    await tester.pump();
    await tester.pump();

    expect(tester.widget<GoGlobe>(find.byType(GoGlobe)).active, isFalse, reason: '页面不可见时地球应停止自转');
  });

  testWidgets('未开启 globe 的页面不渲染地球层', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: const GoPage(child: SizedBox.expand()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(GoGlobe), findsNothing);
  });
}
