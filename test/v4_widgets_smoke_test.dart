import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/services/ai_cost_service.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/article_row.dart';
import 'package:global_overview/v4/widgets/cost_sheet.dart';
import 'package:global_overview/v4/widgets/custom_feed_sheet.dart';
import 'package:global_overview/v4/widgets/import_sheet.dart';
import 'package:global_overview/v4/widgets/practice_sheet.dart';
import 'package:global_overview/v4/widgets/set_label_sheet.dart';

Future<void> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? 'D:/flutter';
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  final loader = FontLoader('Roboto');
  for (final name in [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
  ]) {
    final file = File('${dir.path}/$name');
    if (!file.existsSync()) continue;
    loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await loader.load();
}

ThemeData _theme(bool dark) {
  final base = dark ? V4Theme.dark() : V4Theme.light();
  return base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Roboto'));
}

Widget _wrap(Widget home, {required bool dark, required double textScale}) {
  return MaterialApp(
    theme: _theme(false),
    darkTheme: _theme(true),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: 'Roboto'),
        child: child!,
      ),
    ),
    home: home,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadRoboto();
  });

  testWidgets('文章行在窄屏与大字下不溢出，点击可触发回调', (tester) async {
    addTearDown(tester.view.reset);
    var taps = 0;
    for (final width in [320.0, 412.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final dark in [false, true]) {
          tester.view.physicalSize = Size(width, 720);
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            _wrap(
              Scaffold(
                backgroundColor: dark ? V4Colors.pageDark : V4Colors.page,
                body: V4ArticleRow(
                  title: 'A headline long enough to wrap over two lines',
                  source: 'FeedOverview · 科技',
                  meta: '3 小时前 · 420 词',
                  difficulty: 78,
                  onTap: () => taps++,
                ),
              ),
              dark: dark,
              textScale: scale,
            ),
          );
          await tester.pump();

          expect(
            tester.takeException(),
            isNull,
            reason: 'article row overflowed width=$width scale=$scale',
          );
          expect(find.text('FeedOverview · 科技'), findsOneWidget);
          expect(find.text('进阶'), findsOneWidget);
        }
      }
    }

    await tester.tap(
      find.text('A headline long enough to wrap over two lines'),
    );
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('成本确认弹层在窄屏与大字下不溢出并可取消', (tester) async {
    addTearDown(tester.view.reset);
    const estimate = AiCostEstimate(
      model: 'deepseek-chat',
      inputTokens: 1200,
      outputMin: 300,
      outputMax: 600,
      amountMin: 0.0021,
      amountMax: 0.0042,
      currency: 'CNY',
    );

    for (final width in [320.0, 412.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final dark in [false, true]) {
          tester.view.physicalSize = Size(width, 720);
          tester.view.devicePixelRatio = 1;
          bool? result;
          await tester.pumpWidget(
            _wrap(
              Scaffold(
                backgroundColor: dark ? V4Colors.pageDark : V4Colors.page,
                body: Builder(
                  builder: (context) => Center(
                    child: TextButton(
                      onPressed: () async {
                        result = await showAiCostSheet(context, estimate);
                      },
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
              dark: dark,
              textScale: scale,
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason: 'cost sheet overflowed width=$width scale=$scale',
          );
          expect(find.text('生成前确认'), findsOneWidget);
          expect(find.text('deepseek-chat'), findsOneWidget);

          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(result, isFalse);
        }
      }
    }
  });

  testWidgets('用途标签弹层在窄屏与大字下不溢出并可取消', (tester) async {
    addTearDown(tester.view.reset);
    for (final width in [320.0, 412.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final dark in [false, true]) {
          tester.view.physicalSize = Size(width, 720);
          tester.view.devicePixelRatio = 1;
          String? result;
          await tester.pumpWidget(
            _wrap(
              Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: TextButton(
                      onPressed: () async {
                        result = await showSetLabelSheet(
                          context,
                          current: '考前重做',
                        );
                      },
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
              dark: dark,
              textScale: scale,
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason: 'label sheet overflowed width=$width scale=$scale',
          );
          expect(find.text('用途标签'), findsOneWidget);

          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(result, isNull);
        }
      }
    }
  });

  testWidgets('导入与添加源弹层在窄屏与大字下不溢出', (tester) async {
    addTearDown(tester.view.reset);
    for (final width in [320.0, 412.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final dark in [false, true]) {
          tester.view.physicalSize = Size(width, 720);
          tester.view.devicePixelRatio = 1;
          for (final kind in ['import', 'feed']) {
            await tester.pumpWidget(
              _wrap(
                Scaffold(
                  body: Builder(
                    builder: (context) => Center(
                      child: TextButton(
                        onPressed: () => kind == 'import'
                            ? showImportSheet(context)
                            : showCustomFeedSheet(context),
                        child: Text(kind),
                      ),
                    ),
                  ),
                ),
                dark: dark,
                textScale: scale,
              ),
            );
            await tester.tap(find.text(kind));
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$kind sheet overflowed width=$width scale=$scale',
            );
            await tester.tap(find.text('取消'));
            await tester.pumpAndSettle();
          }
        }
      }
    }
  });

  testWidgets('出题弹层在窄屏与大字下不溢出', (tester) async {
    addTearDown(tester.view.reset);
    for (final width in [320.0, 412.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final dark in [false, true]) {
          tester.view.physicalSize = Size(width, 720);
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            _wrap(
              Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: TextButton(
                      onPressed: () => showPracticeSheet(context),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
              dark: dark,
              textScale: scale,
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason: 'practice sheet overflowed width=$width scale=$scale',
          );
          expect(find.text('出题设置'), findsOneWidget);

          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
        }
      }
    }
  });

  testWidgets('成本确认弹层在确认时返回 true', (tester) async {
    const estimate = AiCostEstimate(
      model: 'gpt-4o',
      inputTokens: 800,
      outputMin: 100,
      outputMax: 200,
    );
    bool? result;
    await tester.pumpWidget(
      _wrap(
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await showAiCostSheet(context, estimate);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        dark: false,
        textScale: 1,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('无法估算金额'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('v4-cost-confirm')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
