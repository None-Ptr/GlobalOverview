import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum V4ThemeMode { system, light, dark }

extension V4ThemeModeX on V4ThemeMode {
  String get label => switch (this) {
    V4ThemeMode.system => '跟随系统',
    V4ThemeMode.light => '浅色',
    V4ThemeMode.dark => '深色',
  };

  ThemeMode get themeMode => switch (this) {
    V4ThemeMode.system => ThemeMode.system,
    V4ThemeMode.light => ThemeMode.light,
    V4ThemeMode.dark => ThemeMode.dark,
  };
}

class V4ThemeModeStore {
  static const key = 'v4_theme_mode';

  Future<V4ThemeMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    return V4ThemeMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => V4ThemeMode.system,
    );
  }

  Future<void> save(V4ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, mode.name);
  }
}

class V4ThemeModeNotifier extends Notifier<V4ThemeMode> {
  final V4ThemeModeStore _store = V4ThemeModeStore();
  bool _userSelected = false;

  @override
  V4ThemeMode build() => V4ThemeMode.system;

  /// Applies a mode loaded before the first frame without persisting it.
  void seed(V4ThemeMode mode) {
    _userSelected = true;
    state = mode;
  }

  Future<void> load() async {
    final mode = await _store.load();
    if (_userSelected) return;
    state = mode;
  }

  Future<void> setMode(V4ThemeMode mode) async {
    _userSelected = true;
    state = mode;
    await _store.save(mode);
  }
}

final v4ThemeModeProvider = NotifierProvider<V4ThemeModeNotifier, V4ThemeMode>(
  V4ThemeModeNotifier.new,
);
