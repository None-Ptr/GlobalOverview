import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

void main() {
  test('深浅主题都保留 TDesign 扩展并注册 V4 Token', () {
    for (final theme in [V4Theme.light(), V4Theme.dark()]) {
      expect(theme.extension<TThemeData>(), isNotNull);
      expect(theme.extension<V4Palette>(), isNotNull);
    }
    expect(V4Theme.dark().extension<V4Palette>(), V4Palette.dark);
    expect(V4Theme.light().extension<V4Palette>(), V4Palette.light);
  });

  testWidgets('深色主题解析深色 Token 与文字颜色', (tester) async {
    late V4Palette palette;
    late TextStyle body;
    late TextStyle caption;

    await tester.pumpWidget(
      MaterialApp(
        theme: V4Theme.dark(),
        home: Builder(
          builder: (context) {
            palette = context.v4;
            body = context.v4Type.body;
            caption = context.v4Type.caption;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(palette.ink, V4Palette.dark.ink);
    expect(palette.page, const Color(0xFF10151C));
    expect(palette.surface, const Color(0xFF171E27));
    expect(body.color, V4Palette.dark.ink);
    expect(caption.color, V4Palette.dark.inkMuted);
  });

  testWidgets('浅色主题解析浅色 Token 与文字颜色', (tester) async {
    late V4Palette palette;
    late TextStyle body;

    await tester.pumpWidget(
      MaterialApp(
        theme: V4Theme.light(),
        home: Builder(
          builder: (context) {
            palette = context.v4;
            body = context.v4Type.body;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(palette.ink, const Color(0xFF17212B));
    expect(palette.page, const Color(0xFFF4F6F8));
    expect(body.color, const Color(0xFF17212B));
  });

  testWidgets('没有注册扩展时回退到浅色 Token', (tester) async {
    late V4Palette palette;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            palette = context.v4;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(palette.ink, V4Palette.light.ink);
  });
}
