import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/v4/screens/about_screen.dart';
import 'package:global_overview/v4/screens/appearance_screen.dart';
import 'package:global_overview/v4/screens/data_screen.dart';
import 'package:global_overview/v4/screens/export_screen.dart';
import 'package:global_overview/v4/screens/fetch_screen.dart';
import 'package:global_overview/v4/screens/learning_screen.dart';
import 'package:global_overview/v4/screens/mine_screen.dart';
import 'package:global_overview/v4/screens/model_form_screen.dart';
import 'package:global_overview/v4/screens/model_screen.dart';
import 'package:global_overview/v4/screens/onboarding_screen.dart';
import 'package:global_overview/v4/screens/plan_screen.dart';
import 'package:global_overview/v4/screens/preferences_screen.dart';
import 'package:global_overview/v4/screens/quiz_screen.dart';
import 'package:global_overview/v4/screens/reader_screen.dart';
import 'package:global_overview/v4/screens/reading_screen.dart';
import 'package:global_overview/v4/screens/review_screen.dart';
import 'package:global_overview/v4/screens/source_screen.dart';
import 'package:global_overview/v4/screens/today_screen.dart';
import 'package:global_overview/v4/screens/translate_form_screen.dart';
import 'package:global_overview/v4/screens/usage_ledger_screen.dart';
import 'package:global_overview/v4/screens/vocab_screen.dart';
import 'package:global_overview/v4/screens/wrong_screen.dart';
import 'package:global_overview/v4/services/onboarding_service.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_db.dart';

class _ReaderDb extends DbService {
  @override
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?>? params,
  ]) async {
    if (sql.contains('FROM articles')) {
      return [
        {
          'title': 'A readable article',
          'sourceUrl': 'https://example.com/a',
          'html': '<p>body</p>',
          'blocks': '[{"type":"p","text":"First paragraph."}]',
          'wordCount': 120,
        },
      ];
    }
    return [];
  }
}

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

ThemeData _withRoboto(ThemeData base) =>
    base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Roboto'));

class _Case {
  final Widget Function() build;
  final DbService? db;
  const _Case(this.build, {this.db});

  DbService get database => db ?? FakeDb();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadRoboto();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const profile = V4Profile(completed: true);

  final cases = <String, _Case>{
    '今日': _Case(() => V4TodayScreen(profile: profile, onOpenReading: () {})),
    '阅读': _Case(() => const V4ReadingScreen(profile: profile)),
    '学习': _Case(() => const V4LearningScreen()),
    '词汇': _Case(() => const V4VocabScreen()),
    '句子': _Case(() => const V4SentencesScreen()),
    '我的': _Case(() => const V4MineScreen(profile: profile)),
    '外观与阅读': _Case(() => const V4AppearanceScreen()),
    '数据管理': _Case(() => const V4DataScreen()),
    '来源与加速': _Case(() => const V4SourceScreen()),
    'AI 用量': _Case(() => const V4UsageLedgerScreen()),
    '阅读器': _Case(() => const V4ReaderScreen(articleId: 1), db: _ReaderDb()),
    '精读单': _Case(() => const V4PlanScreen(), db: RichFakeDb()),
    '错题本': _Case(() => const V4WrongScreen(), db: RichFakeDb()),
    '题目': _Case(() => const V4QuizScreen(setId: 1), db: RichFakeDb()),
    '导出': _Case(() => const V4ExportScreen(articleId: 1), db: RichFakeDb()),
    '复习': _Case(() => const V4ReviewScreen(), db: RichFakeDb()),
    '学习偏好': _Case(() => const V4PreferencesScreen(), db: RichFakeDb()),
    'AI 模型': _Case(() => const V4ModelScreen(), db: RichFakeDb()),
    '新增模型': _Case(() => const V4ModelFormScreen(), db: RichFakeDb()),
    '翻译接口': _Case(() => const V4TranslateFormScreen(), db: RichFakeDb()),
    '抓取设置': _Case(() => const V4FetchScreen(), db: RichFakeDb()),
    '关于': _Case(() => const V4AboutScreen(), db: RichFakeDb()),
    '首启引导': _Case(
      () =>
          V4OnboardingScreen(service: OnboardingService(), onComplete: (_) {}),
    ),
  };

  Widget app({
    required Widget home,
    required DbService db,
    required AppConfigService config,
    required bool dark,
  }) {
    return ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db),
        appConfigProvider.overrideWith((ref) => config),
      ],
      child: MaterialApp(
        theme: _withRoboto(V4Theme.light()),
        darkTheme: _withRoboto(V4Theme.dark()),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: 'Roboto'),
          child: child!,
        ),
        home: Scaffold(
          backgroundColor: dark ? V4Colors.pageDark : V4Colors.page,
          body: home,
        ),
      ),
    );
  }

  for (final entry in cases.entries) {
    // Text contrast is covered by v4_contrast_tokens_test: the widget-level
    // guideline cannot resolve a background through the V4 theme and reports
    // ~1.4:1 for every label, which is a harness artefact, not a real result.
    testWidgets('${entry.key} 的点击区域与语义标签达标', (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final dark in [false, true]) {
        final config = AppConfigService();
        await config.init();
        await tester.pumpWidget(
          app(
            home: entry.value.build(),
            db: entry.value.database,
            config: config,
            dark: dark,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final handle = tester.ensureSemantics();
        // The V4 spec sets hitTarget to 44x44 minimum (primary actions 48),
        // which is the 44x44 guideline, not Android's 48x48 one.
        await expectLater(
          tester,
          meetsGuideline(iOSTapTargetGuideline),
          reason: '${entry.key} tap target below 44x44 (dark=$dark)',
        );
        await expectLater(
          tester,
          meetsGuideline(labeledTapTargetGuideline),
          reason: '${entry.key} tap target without label (dark=$dark)',
        );
        handle.dispose();
      }
    });
  }
}
