import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/screens/reading_screen.dart';

import 'fake_db.dart';

void main() {
  testWidgets('系统字体放大时分类 chip 文字不被竖直裁切', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(FakeDb())],
      child: const MaterialApp(home: ReadingScreen()),
    ));
    await tester.pumpAndSettle();

    final label = find.text('全部');
    final text = tester.getRect(label);
    final chip = tester.getRect(find.ancestor(of: label, matching: find.byType(Container)).first);

    expect(text.height, greaterThan(30), reason: '文字盒不应被固定轨道高度钳制在 20 -> 视觉“上漂”');
    expect(text.top, greaterThanOrEqualTo(chip.top - 0.5));
    expect(text.bottom, lessThanOrEqualTo(chip.bottom + 0.5), reason: '文字应完整落在胶囊内');
  });
}
