import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/telescope_icon.dart';

void main() {
  testWidgets('望远镜图标可渲染并提供语义标签', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: V4TelescopeIcon(size: 24, color: V4Colors.brand)),
        ),
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.bySemanticsLabel('精读'), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
