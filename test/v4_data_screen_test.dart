import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/v4/screens/data_screen.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('数据管理展示学习数据、缓存与危险区', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(FakeDb())],
        child: MaterialApp(
          theme: V4Theme.light(),
          home: const V4DataScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('数据管理'), findsOneWidget);
    expect(find.text('学习数据'), findsOneWidget);
    expect(find.text('文章缓存'), findsOneWidget);
    expect(find.text('V3 迁移备份'), findsOneWidget);
    expect(find.text('危险区'), findsOneWidget);
    expect(find.byKey(const ValueKey('v4-data-export')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('清空学习数据需要输入确认文字并二次确认', (tester) async {
    var wiped = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(FakeDb())],
        child: MaterialApp(
          theme: V4Theme.light(),
          home: V4DataScreen(onWiped: () => wiped = true),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(find.text('清空学习数据'), findsWidgets);
    final confirm = tester.widget<TextButton>(
      find.byKey(const ValueKey('v4-wipe-confirm')),
    );
    expect(confirm.onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('v4-wipe-input')),
      '清空',
    );
    await tester.pump();

    final enabled = tester.widget<TextButton>(
      find.byKey(const ValueKey('v4-wipe-confirm')),
    );
    expect(enabled.onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('v4-wipe-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('最后确认'), findsOneWidget);
    expect(wiped, isFalse);

    await tester.tap(find.text('永久删除'));
    await tester.pumpAndSettle();
    expect(wiped, isTrue);
  });
}
