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
import 'package:global_overview/v4/screens/migration_screen.dart';
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
import 'package:global_overview/v4/services/migration_service.dart';
import 'package:global_overview/v4/services/onboarding_service.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_db.dart';

/// Article row so the reader has something to lay out.
class _ReaderDb extends DbService {
  @override
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?>? params,
  ]) async {
    if (sql.contains('FROM question_sets s')) {
      return [
        {
          'id': 7,
          'createdAt': DateTime(2026, 11, 25, 14, 32).millisecondsSinceEpoch,
          'questionCount': 5,
          'attempts': 3,
          'correctAttempts': 2,
          'label': '六级阅读细节题',
        },
      ];
    }
    if (sql.contains('FROM articles')) {
      return [
        {
          'title': 'A reasonably long headline for the reading layout',
          'sourceUrl': 'https://example.com/a',
          'html': '<p>body</p>',
          'blocks':
              '[{"type":"p","text":"First paragraph that is long enough to wrap across more than one line on a narrow screen."},'
              '{"type":"p","text":"Second paragraph."}]',
          'wordCount': 120,
        },
      ];
    }
    return [];
  }
}

/// Rows for the quiz, wrong book, plan and export screens so their cards,
/// not just their empty states, get laid out.
class _RichDb extends RichFakeDb {}

class _FakeMigrationStore implements V4MigrationStore {
  @override
  Future<V4MigrationSummary> inspect() async => const V4MigrationSummary(
    vocabWords: 12,
    vocabOccurrences: 30,
    questionSets: 2,
    questions: 8,
    answers: 40,
    wrongAnswers: 5,
  );

  @override
  Future<bool> isComplete() async => false;

  @override
  Future<String?> migrate() async => null;
}

class _Case {
  final Widget Function() build;
  final DbService? db;
  const _Case(this.build, {this.db});

  DbService get database => db ?? FakeDb();
}

const _widths = [320.0, 360.0, 412.0, 600.0];
const _scales = [1.0, 1.3, 2.0];

/// The test environment renders every glyph as a 1em box, which makes Latin
/// text far wider than on a device. Loading Roboto gives realistic widths;
/// CJK still falls back to 1em boxes, which matches real CJK metrics.
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
    final bytes = file.readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

ThemeData _withRoboto(ThemeData base) =>
    base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Roboto'));

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
    '精读单': _Case(() => const V4PlanScreen(), db: _RichDb()),
    '错题本': _Case(() => const V4WrongScreen(), db: _RichDb()),
    '题目': _Case(() => const V4QuizScreen(setId: 1), db: _RichDb()),
    '导出': _Case(
      () => const V4ExportScreen(articleId: 1),
      db: _RichDb(),
    ),
    '复习': _Case(() => const V4ReviewScreen(), db: _RichDb()),
    '学习偏好': _Case(() => const V4PreferencesScreen(), db: _RichDb()),
    'AI 模型': _Case(() => const V4ModelScreen(), db: _RichDb()),
    '新增模型': _Case(() => const V4ModelFormScreen(), db: _RichDb()),
    '翻译接口': _Case(() => const V4TranslateFormScreen(), db: _RichDb()),
    '抓取设置': _Case(() => const V4FetchScreen(), db: _RichDb()),
    '关于': _Case(() => const V4AboutScreen(), db: _RichDb()),
    '首启引导': _Case(
      () =>
          V4OnboardingScreen(service: OnboardingService(), onComplete: (_) {}),
    ),
    '迁移': _Case(
      () => V4MigrationScreen(store: _FakeMigrationStore(), onComplete: (_) {}),
    ),
  };

  Widget app({
    required Widget home,
    required DbService db,
    required AppConfigService config,
    required bool dark,
    required double textScale,
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: 'Roboto'),
            child: child!,
          ),
        ),
        home: Material(type: MaterialType.transparency, child: home),
      ),
    );
  }

  for (final entry in cases.entries) {
    testWidgets('${entry.key} 在各种宽度与字号下不溢出', (tester) async {
      addTearDown(tester.view.reset);
      for (final width in _widths) {
        for (final scale in _scales) {
          for (final dark in [false, true]) {
            tester.view.physicalSize = Size(width, 720);
            tester.view.devicePixelRatio = 1;
            final config = AppConfigService();
            await config.init();
            await tester.pumpWidget(
              app(
                home: entry.value.build(),
                db: entry.value.database,
                config: config,
                dark: dark,
                textScale: scale,
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 50));

            final exception = tester.takeException();
            expect(
              exception,
              isNull,
              reason:
                  '${entry.key} overflowed at width=$width scale=$scale '
                  'dark=$dark',
            );
          }
        }
      }
    });
  }
}
