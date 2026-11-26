import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/v4/screens/appearance_screen.dart';
import 'package:global_overview/v4/services/theme_mode_service.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('外观页可切换深浅色并保存', (tester) async {
    final config = AppConfigService();
    await config.init();

    final container = ProviderContainer(
      overrides: [appConfigProvider.overrideWith((ref) => config)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: V4Theme.light(),
          home: const V4AppearanceScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('浅色'), findsWidgets);
    expect(find.text('深色'), findsWidgets);
    expect(find.text('阅读默认字号'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('v4-theme-dark')));
    await tester.pump();

    expect(container.read(v4ThemeModeProvider), V4ThemeMode.dark);
    expect(await V4ThemeModeStore().load(), V4ThemeMode.dark);
  });

  testWidgets('调整字号写入阅读设置', (tester) async {
    final config = AppConfigService();
    await config.init();

    final container = ProviderContainer(
      overrides: [appConfigProvider.overrideWith((ref) => config)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: V4Theme.light(),
          home: const V4AppearanceScreen(),
        ),
      ),
    );
    await tester.pump();

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('v4-font-size')),
    );
    expect(slider.value, 18);

    await tester.tap(find.byKey(const ValueKey('v4-line-height-2.1')));
    await tester.pump();

    expect(config.lineHeight, 2.1);
  });

  testWidgets('历史字号超出 V4 范围时钳制到 16–24', (tester) async {
    final config = AppConfigService();
    await config.init();
    await config.setReader(fontSize: 14);

    final container = ProviderContainer(
      overrides: [appConfigProvider.overrideWith((ref) => config)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: V4Theme.light(),
          home: const V4AppearanceScreen(),
        ),
      ),
    );
    await tester.pump();

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('v4-font-size')),
    );
    expect(slider.value, 16);
    expect(tester.takeException(), isNull);
  });

  testWidgets('外观页同时展示浅色与深色预览', (tester) async {
    final config = AppConfigService();
    await config.init();

    final container = ProviderContainer(
      overrides: [appConfigProvider.overrideWith((ref) => config)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: V4Theme.light(),
          home: const V4AppearanceScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('v4-preview-light')), findsOneWidget);
    expect(find.byKey(const ValueKey('v4-preview-dark')), findsOneWidget);
  });
}
