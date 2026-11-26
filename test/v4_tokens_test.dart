import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

void main() {
  test('copyWith 只替换传入的字段', () {
    final changed = V4Palette.light.copyWith(ink: const Color(0xFF000000));
    expect(changed.ink, const Color(0xFF000000));
    expect(changed.page, V4Palette.light.page);
    expect(changed.brand, V4Palette.light.brand);
    expect(changed.error, V4Palette.light.error);
  });

  test('copyWith 不传参数时保持原值', () {
    final same = V4Palette.dark.copyWith();
    expect(same.page, V4Palette.dark.page);
    expect(same.ink, V4Palette.dark.ink);
    expect(same.surfaceSubtle, V4Palette.dark.surfaceSubtle);
  });

  test('lerp 在过半后切到目标调色板', () {
    expect(V4Palette.light.lerp(V4Palette.dark, 0.2), V4Palette.light);
    expect(V4Palette.light.lerp(V4Palette.dark, 0.5), V4Palette.dark);
    expect(V4Palette.light.lerp(null, 0.9), V4Palette.light);
  });

  test('V4Type 的文字颜色跟随调色板', () {
    final light = V4Type(V4Palette.light);
    final dark = V4Type(V4Palette.dark);
    expect(light.pageTitle.color, V4Colors.ink);
    expect(dark.pageTitle.color, V4Colors.inkDark);
    expect(light.label.color, V4Colors.inkSecondary);
    expect(dark.label.color, V4Colors.inkSecondaryDark);
    expect(light.caption.color, V4Colors.inkMuted);
    expect(dark.caption.color, V4Colors.inkMutedDark);
    expect(dark.articleBody.color, V4Colors.articleInkDark);
    expect(light.articleBody.color, V4Colors.articleInk);
    expect(light.articleBody.fontFamily, V4Fonts.reading);
  });

  test('V4Type 的字号与行高符合规范', () {
    final type = V4Type(V4Palette.light);
    expect(type.pageTitle.fontSize, 24);
    expect(type.sectionTitle.fontSize, 20);
    expect(type.body.fontSize, 16);
    expect(type.label.fontSize, 14);
    expect(type.caption.fontSize, 13);
    expect(type.articleBody.fontSize, 18);
    expect(type.articleBody.height, 1.75);
  });

  test('深色调色板与浅色调色板逐项不同', () {
    expect(V4Palette.dark.page, isNot(V4Palette.light.page));
    expect(V4Palette.dark.surface, isNot(V4Palette.light.surface));
    expect(V4Palette.dark.ink, isNot(V4Palette.light.ink));
    expect(V4Palette.dark.brand, isNot(V4Palette.light.brand));
    expect(V4Palette.dark.onBrand, isNot(V4Palette.light.onBrand));
  });

  test('TDesign 拿到品牌色与反色文字，主按钮不会落到默认灰', () {
    final light = V4Theme.tokens;
    final dark = V4Theme.tokens.dark!;

    expect(light.brandColor, V4Colors.brand);
    expect(light.textColorAnti, V4Colors.onBrand);
    expect(dark.brandColor, V4Colors.brandDark);
    expect(dark.textColorAnti, V4Colors.onBrandDark);
    expect(dark.textColorAnti, isNot(light.textColorAnti));
  });
}
