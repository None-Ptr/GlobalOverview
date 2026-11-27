import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/widgets/observation_ring.dart';

void main() {
  testWidgets('观测环展示真实进度并提供语义', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: V4ObservationRing(current: 3, goal: 5)),
        ),
      ),
    );

    expect(find.text('3'), findsOneWidget);
    expect(find.bySemanticsLabel('今日学习 3，目标 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
