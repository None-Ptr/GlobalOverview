import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';

/// V4 主题：TDesign 负责组件行为，V4 Token 负责阅读与品牌。
class V4Theme {
  V4Theme._();

  static const _themeJson = r'''
{
  "v4Light": {"color": {
    "brandColor": "#0052D9",
    "brandColorLight": "#E6EEFC",
    "brandColorFocus": "#D7E3FB",
    "brandColorActive": "#003FB0",
    "brandColorDisabled": "#A8B7CE",
    "bgColorPage": "#F4F6F8",
    "bgColorContainer": "#FCFDFE",
    "textColorPrimary": "#17212B",
    "textColorSecondary": "#52606D",
    "textColorPlaceholder": "#5F6C7A",
    "textColorAnti": "#FCFDFE",
    "componentBorder": "#73808E",
    "componentStroke": "#D8DEE5"
  }},
  "v4Dark": {"color": {
    "brandColor": "#8FB3FF",
    "brandColorLight": "#1C2A43",
    "brandColorFocus": "#263B5F",
    "brandColorActive": "#B5CBFF",
    "brandColorDisabled": "#465468",
    "bgColorPage": "#10151C",
    "bgColorContainer": "#171E27",
    "textColorPrimary": "#EDF1F5",
    "textColorSecondary": "#AAB4C0",
    "textColorPlaceholder": "#8D99A7",
    "textColorAnti": "#10151C",
    "componentBorder": "#718195",
    "componentStroke": "#35404D"
  }}
}
''';

  static TThemeData get tokens =>
      TThemeData.fromJson('v4Light', _themeJson, darkName: 'v4Dark')!;

  static ThemeData light() {
    final base = TThemeBuilder.light(tokens);
    final themed = base.mergeExtension(V4Palette.light);
    return themed.copyWith(
      scaffoldBackgroundColor: V4Colors.page,
      canvasColor: V4Colors.page,
      dividerColor: V4Colors.rule,
      appBarTheme: const AppBarTheme(
        backgroundColor: V4Colors.page,
        foregroundColor: V4Colors.ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      iconTheme: const IconThemeData(color: V4Colors.inkSecondary),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: V4Colors.surface,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        contentTextStyle: const TextStyle(
          fontSize: 14,
          height: 1.4,
          color: V4Colors.ink,
        ),
        actionTextColor: V4Colors.brand,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(V4Radius.card),
          side: const BorderSide(color: V4Colors.rule),
        ),
      ),
      colorScheme: base.colorScheme.copyWith(
        primary: V4Colors.brand,
        onPrimary: V4Colors.onBrand,
        surface: V4Colors.surface,
        onSurface: V4Colors.ink,
        error: V4Colors.error,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: V4Colors.ink,
        displayColor: V4Colors.ink,
      ),
    );
  }

  static ThemeData dark() {
    final base = TThemeBuilder.dark(tokens);
    final themed = base.mergeExtension(V4Palette.dark);
    return themed.copyWith(
      scaffoldBackgroundColor: V4Colors.pageDark,
      canvasColor: V4Colors.pageDark,
      dividerColor: V4Colors.ruleDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: V4Colors.pageDark,
        foregroundColor: V4Colors.inkDark,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      iconTheme: const IconThemeData(color: V4Colors.inkSecondaryDark),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: V4Colors.surfaceDark,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        contentTextStyle: const TextStyle(
          fontSize: 14,
          height: 1.4,
          color: V4Colors.inkDark,
        ),
        actionTextColor: V4Colors.brandDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(V4Radius.card),
          side: const BorderSide(color: V4Colors.ruleDark),
        ),
      ),
      colorScheme: base.colorScheme.copyWith(
        primary: V4Colors.brandDark,
        onPrimary: V4Colors.onBrandDark,
        surface: V4Colors.surfaceDark,
        onSurface: V4Colors.inkDark,
        error: V4Colors.errorDark,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: V4Colors.inkDark,
        displayColor: V4Colors.inkDark,
      ),
    );
  }
}
