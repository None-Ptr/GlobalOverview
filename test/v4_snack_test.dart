import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/v4_snack.dart';

Widget _host(
  void Function(BuildContext context) onShow, {
  bool dark = false,
}) {
  return MaterialApp(
    theme: dark ? V4Theme.dark() : V4Theme.light(),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => onShow(context),
          child: const Text('show'),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('show'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('V4 提示条显示文案、图标与操作，点击操作后回调', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      _host(
        (context) => showV4Snack(
          context,
          '已保存',
          tone: V4SnackTone.success,
          actionLabel: '撤销',
          onAction: () => tapped++,
        ),
      ),
    );
    await _open(tester);

    expect(find.text('已保存'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tapped, 1);
  });

  testWidgets('V4 提示条在深色下用深色墨色', (tester) async {
    await tester.pumpWidget(
      _host(
        (context) =>
            showV4Snack(context, '导出失败', tone: V4SnackTone.error),
        dark: true,
      ),
    );
    await _open(tester);

    final message = tester.widget<Text>(find.text('导出失败'));
    expect(message.style?.color, V4Colors.inkDark);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });
}
