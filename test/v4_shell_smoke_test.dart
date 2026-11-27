import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/v4/screens/v4_shell.dart';
import 'package:global_overview/v4/services/onboarding_service.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('V4 壳在空数据库下可启动且四 Tab 可见', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(FakeDb())],
        child: MaterialApp(
          theme: V4Theme.light(),
          home: const V4Shell(profile: V4Profile(completed: true)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('GlobalOverview'), findsOneWidget);
    expect(find.text('今日'), findsWidgets);
    expect(find.text('阅读'), findsWidgets);
    expect(find.text('学习'), findsWidgets);
    expect(find.text('我的'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
