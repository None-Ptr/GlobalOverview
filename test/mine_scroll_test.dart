import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/screens/mine_screen.dart';

import 'fake_db.dart';

const _footer = 'GlobalOverview · By ShaDouBuShi & _Null_Ptr';

void main() {
  testWidgets('我的页内容超高时仍可滚动', (tester) async {
    tester.view.physicalSize = const Size(400, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(FakeDb())],
      child: const MaterialApp(home: MineScreen()),
    ));
    await tester.pumpAndSettle();

    final footer = find.text(_footer);
    expect(footer, findsOneWidget);

    final before = tester.getTopLeft(footer).dy;
    expect(before, greaterThan(640), reason: '前置条件：内容应超出视口');

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -240));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(footer).dy, lessThan(before), reason: '页面应能向上拖动');
  });
}
