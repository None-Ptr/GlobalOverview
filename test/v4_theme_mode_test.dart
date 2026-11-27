import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/services/theme_mode_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('默认跟随系统，保存后可恢复', () async {
    final store = V4ThemeModeStore();
    expect(await store.load(), V4ThemeMode.system);

    await store.save(V4ThemeMode.dark);
    expect(await store.load(), V4ThemeMode.dark);
  });

  test('模式映射到 ThemeMode', () {
    expect(V4ThemeMode.system.themeMode, ThemeMode.system);
    expect(V4ThemeMode.light.themeMode, ThemeMode.light);
    expect(V4ThemeMode.dark.themeMode, ThemeMode.dark);
  });

  test('Notifier 载入并持久化模式', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(v4ThemeModeProvider.notifier);

    await notifier.load();
    expect(container.read(v4ThemeModeProvider), V4ThemeMode.system);

    await notifier.setMode(V4ThemeMode.light);
    expect(container.read(v4ThemeModeProvider), V4ThemeMode.light);
    expect(await V4ThemeModeStore().load(), V4ThemeMode.light);
  });

  test('启动时预置的模式不会被稍后的读取覆盖', () async {
    await V4ThemeModeStore().save(V4ThemeMode.light);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(v4ThemeModeProvider.notifier);

    notifier.seed(V4ThemeMode.dark);
    expect(container.read(v4ThemeModeProvider), V4ThemeMode.dark);

    await notifier.load();
    expect(container.read(v4ThemeModeProvider), V4ThemeMode.dark);
  });
}
