import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/v4/screens/source_screen.dart';
import 'package:global_overview/v4/services/feedoverview_service.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(FakeDb())],
        child: MaterialApp(
          theme: V4Theme.light(),
          home: const V4SourceScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('来源页提供官方与自建加速地址', (tester) async {
    await pumpScreen(tester);

    expect(find.text('加速地址'), findsOneWidget);
    expect(find.text('官方加速'), findsOneWidget);
    expect(find.text('自建加速'), findsOneWidget);

    await tester.tap(find.text('自建加速'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('v4-source-url')), findsOneWidget);
  });

  testWidgets('非 HTTPS 自建地址被拒绝且不写入', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('自建加速'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('v4-source-url')));
    await tester.enterText(
      find.byKey(const ValueKey('v4-source-url')),
      'http://example.com/FeedOverview',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('v4-source-save')));
    await tester.tap(find.byKey(const ValueKey('v4-source-save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('HTTPS'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(FeedOverviewService.rootUrlKey), isNull);
  });
}
