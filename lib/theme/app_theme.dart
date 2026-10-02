import 'package:flutter/material.dart';
import 'go_tokens.dart';

/// 兼容旧引用的语义色别名，全部指向 [Go] 令牌。
class GoColors {
  const GoColors._();

  static const lightBg = Go.bg;
  static const lightSurface = Go.surface;
  static const lightPrimary = Go.primary;
  static const lightText = Go.onSurface;
  static const lightSubtleText = Go.onSurface2;
  static const lightBorder = Go.outline;
  static const lightAccent = Go.success;
  static const lightDanger = Go.error;
  static const lightWarn = Go.warning;

  static const darkBg = Go.bg;
  static const darkSurface = Go.surface;
  static const darkPrimary = Go.primary;
  static const darkText = Go.onSurface;
  static const darkSubtleText = Go.onSurface2;
  static const darkBorder = Go.outline;
  static const darkAccent = Go.success;
  static const darkDanger = Go.error;
  static const darkWarn = Go.warning;
}

ThemeData _buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: Go.primary,
    brightness: brightness,
  ).copyWith(
    primary: Go.primary,
    onPrimary: Go.onPrimary,
    primaryContainer: Go.primary95,
    onPrimaryContainer: Go.onPrimaryContainer,
    secondary: Go.secondary,
    onSecondary: Go.onSecondary,
    secondaryContainer: Go.secondaryContainer,
    onSecondaryContainer: Go.onSecondaryContainer,
    tertiary: Go.tertiary,
    onTertiary: Go.onTertiary,
    tertiaryContainer: Go.tertiaryContainer,
    onTertiaryContainer: Go.onTertiaryContainer,
    surface: Go.surface,
    onSurface: Go.onSurface,
    surfaceContainerHighest: Go.surface2,
    outline: Go.outline,
    outlineVariant: Go.surfaceVariant,
    error: Go.error,
    onError: Go.onDanger,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: Go.bg,
    splashFactory: InkRipple.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: Go.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: Go.onSurface,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Go.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Go.rLg)),
    ),
    dividerColor: Go.outline,
    dividerTheme: const DividerThemeData(color: Go.outline, thickness: 0.5, space: 0.5),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: Go.fsBodySm, height: Go.lhNormal, color: Go.onSurface),
      bodyLarge: TextStyle(fontSize: Go.fsBody, height: Go.lhNormal, color: Go.onSurface),
      titleMedium: TextStyle(fontSize: Go.fsTitle, fontWeight: FontWeight.w600, color: Go.onSurface),
      titleSmall: TextStyle(fontSize: Go.fsBodySm, fontWeight: FontWeight.w500, color: Go.onSurface),
      labelMedium: TextStyle(fontSize: Go.fsMeta, color: Go.onSurface3),
      labelSmall: TextStyle(fontSize: Go.fsCap, color: Go.onSurface3),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
  );
}

ThemeData buildLightTheme() => _buildTheme(Brightness.light);
ThemeData buildDarkTheme() => _buildTheme(Brightness.dark);

/// 在任意 BuildContext 上取语义 token 的便捷扩展。
extension GoColorExt on BuildContext {
  ColorScheme get go => Theme.of(this).colorScheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
