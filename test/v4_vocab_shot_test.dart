import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/llm_service.dart';
import 'package:global_overview/services/vocab_service.dart';
import 'package:global_overview/v4/screens/vocab_screen.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';

import 'fake_db.dart';
import 'shot_fonts.dart';

/// 词汇页截图。默认跳过，重新生成：
/// `$env:HOME_SHOT=1; flutter test test/v4_vocab_shot_test.dart --update-goldens`
final _enabled = Platform.environment['HOME_SHOT'] == '1';

class _ShotVocab extends VocabService {
  _ShotVocab()
    : super(FakeDb(), LlmService(HttpService(), AppConfigService()));

  static Map<String, dynamic> _row(
    String head,
    String zh,
    int occ,
    int sources,
    int dueInDays,
  ) => {
    'head': head,
    'kind': head.contains(' ') ? 'phrase' : 'word',
    'zh': zh,
    'occCount': occ,
    'sourceCount': sources,
    'fsrs_due': DateTime.now()
        .add(Duration(days: dueInDays))
        .millisecondsSinceEpoch,
  };

  @override
  Future<void> syncHeadsFromCache() async {}

  @override
  Future<List<Map<String, dynamic>>> getHeads() async => [
    _row('hydrothermal', '热液的；与热水有关的', 4, 2, -1),
    _row('microbe', '微生物', 2, 1, -1),
    _row('push back', '推迟；延缓', 3, 2, -1),
    _row('refuge', '庇护所；避难处', 1, 1, 2),
    _row('ritual', '仪式；惯例', 2, 1, 4),
    _row('curated', '精选的；策划的', 1, 1, 9),
  ];

  @override
  Future<int> dueCount() async => 3;
}

ThemeData _theme(ThemeData base) => base.copyWith(
  textTheme: base.textTheme.apply(
    fontFamily: 'Roboto',
    fontFamilyFallback: const ['CJK'],
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadShotFonts);

  Widget app({required bool dark}) => ProviderScope(
    overrides: [
      dbProvider.overrideWithValue(FakeDb()),
      vocabProvider.overrideWithValue(_ShotVocab()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(V4Theme.light()),
      darkTheme: _theme(V4Theme.dark()),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => DefaultTextStyle.merge(
        style: const TextStyle(
          fontFamily: 'Roboto',
          fontFamilyFallback: ['CJK'],
        ),
        child: child!,
      ),
      home: const V4VocabScreen(),
    ),
  );

  for (final dark in [false, true]) {
    testWidgets(dark ? '词汇页截图（深色）' : '词汇页截图（浅色）', (tester) async {
      tester.view.physicalSize = const Size(824, 1830);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app(dark: dark));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          dark ? 'goldens/vocab_dark.png' : 'goldens/vocab_light.png',
        ),
      );
    }, skip: !_enabled);
  }
}
