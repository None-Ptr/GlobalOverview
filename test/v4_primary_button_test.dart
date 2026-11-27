import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_primary_button.dart';

Widget _app({required ThemeData theme, required Widget child}) {
  return MaterialApp(
    theme: theme,
    home: Scaffold(body: Center(child: child)),
  );
}

Color? _labelColor(WidgetTester tester, String label) {
  final rich = tester.widget<RichText>(
    find.descendant(of: find.text(label), matching: find.byType(RichText)),
  );
  return rich.text.style?.color;
}

void main() {
  testWidgets('深色主按钮标签用反色墨，不是 TDesign 的白字', (tester) async {
    await tester.pumpWidget(
      _app(
        theme: V4Theme.dark(),
        child: V4PrimaryButton(
          onPressed: () {},
          child: const Text('生成精读练习'),
        ),
      ),
    );

    expect(_labelColor(tester, '生成精读练习'), V4Palette.dark.onBrand);
  });

  testWidgets('浅色主按钮标签同样用反色墨', (tester) async {
    await tester.pumpWidget(
      _app(
        theme: V4Theme.light(),
        child: V4PrimaryButton(
          onPressed: () {},
          child: const Text('保存'),
        ),
      ),
    );

    expect(_labelColor(tester, '保存'), V4Palette.light.onBrand);
  });

  testWidgets('禁用时交回 TDesign 自己的配色', (tester) async {
    await tester.pumpWidget(
      _app(
        theme: V4Theme.dark(),
        child: const V4PrimaryButton(
          onPressed: null,
          child: Text('生成精读练习'),
        ),
      ),
    );

    expect(_labelColor(tester, '生成精读练习'), isNot(V4Palette.dark.onBrand));
  });
}
