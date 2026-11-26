import 'package:flutter/material.dart';

class V4Colors {
  V4Colors._();

  static const page = Color(0xFFF4F6F8);
  static const surface = Color(0xFFFCFDFE);
  static const surfaceSubtle = Color(0xFFEAF0F5);
  static const ink = Color(0xFF17212B);
  static const inkSecondary = Color(0xFF52606D);
  static const inkMuted = Color(0xFF5F6C7A);
  static const articleInk = Color(0xFF17212B);
  static const rule = Color(0xFFD8DEE5);
  static const brand = Color(0xFF0052D9);
  static const onBrand = Color(0xFFFCFDFE);
  static const ai = Color(0xFF6F42C1);
  static const success = Color(0xFF137A52);
  static const warning = Color(0xFF9A5200);
  static const error = Color(0xFFC9353F);

  static const pageDark = Color(0xFF10151C);
  static const surfaceDark = Color(0xFF171E27);
  static const surfaceSubtleDark = Color(0xFF1E2732);
  static const inkDark = Color(0xFFEDF1F5);
  static const inkSecondaryDark = Color(0xFFAAB4C0);
  static const inkMutedDark = Color(0xFF8D99A7);
  static const articleInkDark = Color(0xFFDDE3EA);
  static const ruleDark = Color(0xFF35404D);
  static const brandDark = Color(0xFF8FB3FF);
  static const onBrandDark = Color(0xFF10151C);
  static const aiDark = Color(0xFFB9A0FF);
  static const successDark = Color(0xFF63C99A);
  static const warningDark = Color(0xFFE7B66A);
  static const errorDark = Color(0xFFF08A92);
}

/// Resolves design tokens for the active brightness.
class V4Palette extends ThemeExtension<V4Palette> {
  final Color page;
  final Color surface;
  final Color surfaceSubtle;
  final Color ink;
  final Color inkSecondary;
  final Color inkMuted;
  final Color articleInk;
  final Color rule;
  final Color brand;
  final Color onBrand;
  final Color ai;
  final Color success;
  final Color warning;
  final Color error;

  const V4Palette({
    required this.page,
    required this.surface,
    required this.surfaceSubtle,
    required this.ink,
    required this.inkSecondary,
    required this.inkMuted,
    required this.articleInk,
    required this.rule,
    required this.brand,
    required this.onBrand,
    required this.ai,
    required this.success,
    required this.warning,
    required this.error,
  });

  static const light = V4Palette(
    page: V4Colors.page,
    surface: V4Colors.surface,
    surfaceSubtle: V4Colors.surfaceSubtle,
    ink: V4Colors.ink,
    inkSecondary: V4Colors.inkSecondary,
    inkMuted: V4Colors.inkMuted,
    articleInk: V4Colors.articleInk,
    rule: V4Colors.rule,
    brand: V4Colors.brand,
    onBrand: V4Colors.onBrand,
    ai: V4Colors.ai,
    success: V4Colors.success,
    warning: V4Colors.warning,
    error: V4Colors.error,
  );

  static const dark = V4Palette(
    page: V4Colors.pageDark,
    surface: V4Colors.surfaceDark,
    surfaceSubtle: V4Colors.surfaceSubtleDark,
    ink: V4Colors.inkDark,
    inkSecondary: V4Colors.inkSecondaryDark,
    inkMuted: V4Colors.inkMutedDark,
    articleInk: V4Colors.articleInkDark,
    rule: V4Colors.ruleDark,
    brand: V4Colors.brandDark,
    onBrand: V4Colors.onBrandDark,
    ai: V4Colors.aiDark,
    success: V4Colors.successDark,
    warning: V4Colors.warningDark,
    error: V4Colors.errorDark,
  );

  static V4Palette of(BuildContext context) =>
      Theme.of(context).extension<V4Palette>() ?? light;

  @override
  V4Palette copyWith({
    Color? page,
    Color? surface,
    Color? surfaceSubtle,
    Color? ink,
    Color? inkSecondary,
    Color? inkMuted,
    Color? articleInk,
    Color? rule,
    Color? brand,
    Color? onBrand,
    Color? ai,
    Color? success,
    Color? warning,
    Color? error,
  }) {
    return V4Palette(
      page: page ?? this.page,
      surface: surface ?? this.surface,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      ink: ink ?? this.ink,
      inkSecondary: inkSecondary ?? this.inkSecondary,
      inkMuted: inkMuted ?? this.inkMuted,
      articleInk: articleInk ?? this.articleInk,
      rule: rule ?? this.rule,
      brand: brand ?? this.brand,
      onBrand: onBrand ?? this.onBrand,
      ai: ai ?? this.ai,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
    );
  }

  @override
  V4Palette lerp(covariant V4Palette? other, double t) {
    if (other == null || t >= 0.5) return other ?? this;
    return this;
  }
}

class V4Space {
  V4Space._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const huge = 40.0;
}

class V4Radius {
  V4Radius._();
  static const control = 8.0;
  static const card = 12.0;
  static const sheet = 20.0;
}

class V4Fonts {
  V4Fonts._();

  /// Reading face for English article text, bundled in pubspec under the OFL.
  static const reading = 'Literata';
}

/// Typography bound to a palette, so every style carries the active color.
class V4Type {
  final V4Palette c;
  const V4Type(this.c);

  TextStyle get pageTitle => TextStyle(
    fontSize: 24,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: c.ink,
  );
  TextStyle get sectionTitle => TextStyle(
    fontSize: 20,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: c.ink,
  );
  TextStyle get itemTitle => TextStyle(
    fontSize: 16,
    height: 1.45,
    fontWeight: FontWeight.w600,
    color: c.ink,
  );
  TextStyle get body => TextStyle(fontSize: 16, height: 1.6, color: c.ink);
  TextStyle get label =>
      TextStyle(fontSize: 14, height: 1.45, color: c.inkSecondary);
  TextStyle get caption =>
      TextStyle(fontSize: 13, height: 1.45, color: c.inkMuted);
  TextStyle get articleBody => TextStyle(
    fontSize: 18,
    height: 1.75,
    fontFamily: V4Fonts.reading,
    color: c.articleInk,
  );
  TextStyle get articleTitle => TextStyle(
    fontSize: 28,
    height: 1.24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    fontFamily: V4Fonts.reading,
    color: c.articleInk,
  );
  /// One display number per screen: the quiz receipt and the review card.
  TextStyle get displayNumber => TextStyle(
    fontSize: 32,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: c.ink,
  );
  TextStyle get articleLead => TextStyle(
    fontSize: 19,
    height: 1.65,
    fontFamily: V4Fonts.reading,
    color: c.articleInk,
  );
}

/// Wide-screen geometry. Below [wide] the app keeps the phone layout it was
/// drawn for; above it the shell trades the bottom bar for desk chrome.
class V4Layout {
  V4Layout._();

  /// Where the top bar replaces the bottom bar and two columns become possible.
  static const wide = 960.0;

  /// Where the reading desk earns its preview pane.
  static const desk = 1180.0;

  /// Shell content: past this the gutters grow, the grids do not.
  static const content = 1240.0;

  /// One column of settings or a pushed page, centred.
  static const page = 760.0;

  /// Category rail on the reading desk.
  static const rail = 208.0;

  /// Preview pane on the reading desk.
  static const preview = 380.0;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wide;

  static bool isDesk(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desk;
}

extension V4TokenContext on BuildContext {
  V4Palette get v4 => V4Palette.of(this);
  V4Type get v4Type => V4Type(v4);
}
