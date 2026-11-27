import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/v4/screens/appearance_screen.dart';
import 'package:global_overview/v4/screens/data_screen.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpAt(
    WidgetTester tester,
    Widget home, {
    double width = 320,
    double textScale = 2,
  }) async {
    tester.view.physicalSize = Size(width, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: Size(width, 640),
          textScaler: TextScaler.linear(textScale),
        ),
        child: home,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('数据管理在 320dp 与 200% 字号下不裁切', (tester) async {
    await pumpAt(
      tester,
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(FakeDb())],
        child: MaterialApp(
          theme: V4Theme.light(),
          home: const V4DataScreen(),
        ),
      ),
    );

    expect(find.text('数据管理'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('外观页在 320dp 与 200% 字号下不裁切', (tester) async {
    final config = AppConfigService();
    await config.init();
    await pumpAt(
      tester,
      ProviderScope(
        overrides: [appConfigProvider.overrideWith((ref) => config)],
        child: MaterialApp(
          theme: V4Theme.light(),
          home: const V4AppearanceScreen(),
        ),
      ),
    );

    expect(find.text('外观与阅读'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
