import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';

/// WCAG 2.1 relative luminance.
double _luminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _ratio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

class _Pair {
  final String name;
  final Color foreground;
  final Color background;
  final double minimum;
  const _Pair(this.name, this.foreground, this.background, this.minimum);
}

void main() {
  List<_Pair> pairsFor(V4Palette p, String mode) => [
    _Pair('$mode 正文 / 页面', p.ink, p.page, 4.5),
    _Pair('$mode 正文 / 卡片', p.ink, p.surface, 4.5),
    _Pair('$mode 正文 / 次级底', p.ink, p.surfaceSubtle, 4.5),
    _Pair('$mode 次要文字 / 页面', p.inkSecondary, p.page, 4.5),
    _Pair('$mode 次要文字 / 卡片', p.inkSecondary, p.surface, 4.5),
    _Pair('$mode 说明文字 / 页面', p.inkMuted, p.page, 4.5),
    _Pair('$mode 说明文字 / 卡片', p.inkMuted, p.surface, 4.5),
    _Pair('$mode 品牌色 / 页面', p.brand, p.page, 4.5),
    _Pair('$mode 品牌色 / 卡片', p.brand, p.surface, 4.5),
    _Pair('$mode 品牌底上的文字', p.onBrand, p.brand, 4.5),
    _Pair('$mode 错误色 / 页面', p.error, p.page, 4.5),
    _Pair('$mode 警告色 / 页面', p.warning, p.page, 4.5),
    _Pair('$mode 成功色 / 页面', p.success, p.page, 4.5),
    _Pair('$mode AI 色 / 页面', p.ai, p.page, 4.5),
  ];

  test('浅色 Token 满足 WCAG AA 正文对比度', () {
    final failures = <String>[];
    for (final pair in pairsFor(V4Palette.light, '浅色')) {
      final ratio = _ratio(pair.foreground, pair.background);
      if (ratio < pair.minimum) {
        failures.add(
          '${pair.name}: ${ratio.toStringAsFixed(2)} < ${pair.minimum}',
        );
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('深色 Token 满足 WCAG AA 正文对比度', () {
    final failures = <String>[];
    for (final pair in pairsFor(V4Palette.dark, '深色')) {
      final ratio = _ratio(pair.foreground, pair.background);
      if (ratio < pair.minimum) {
        failures.add(
          '${pair.name}: ${ratio.toStringAsFixed(2)} < ${pair.minimum}',
        );
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('浅色与深色页面底色的对比度足够区分', () {
    expect(_ratio(V4Colors.page, V4Colors.pageDark), greaterThan(10));
  });
}
