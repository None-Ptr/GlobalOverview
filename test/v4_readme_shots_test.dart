import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/models/models.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/feeds_service.dart';
import 'package:global_overview/services/habit_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/llm_service.dart';
import 'package:global_overview/services/rss_service.dart';
import 'package:global_overview/services/translate_service.dart';
import 'package:global_overview/services/vocab_service.dart';
import 'package:global_overview/services/word_service.dart';
import 'package:global_overview/v4/screens/guide_screen.dart';
import 'package:global_overview/v4/screens/mine_screen.dart';
import 'package:global_overview/v4/screens/plan_screen.dart';
import 'package:global_overview/v4/screens/quiz_screen.dart';
import 'package:global_overview/v4/screens/reader_screen.dart';
import 'package:global_overview/v4/screens/reading_screen.dart';
import 'package:global_overview/v4/screens/v4_shell.dart';
import 'package:global_overview/v4/screens/vocab_screen.dart';
import 'package:global_overview/v4/services/onboarding_service.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:global_overview/v4/widgets/word_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_db.dart';
import 'shot_fonts.dart';

/// Writes the README screenshots. Skipped by default so another machine's
/// fonts cannot fail the suite. Regenerate with:
/// `$env:README_SHOTS=1; flutter test test/v4_readme_shots_test.dart --update-goldens`
final _enabled = Platform.environment['README_SHOTS'] == '1';

class _ShotDb extends DbService {
  static const _title = 'Deep-sea vents push the origin of life further back';
  static const _blocks =
      '[{"type":"p","text":"Why it is here: the finding comes from a vent field mapped last spring."},'
      '{"type":"p","text":"A team sampling warm fissures on the ocean floor has found microbes that build their own food from dissolved minerals, without sunlight."},'
      '{"type":"p","text":"The chemistry at the vent is close to what early oceans could have offered, which is why the result matters beyond the field."},'
      '{"type":"p","text":"Other groups have reported similar communities, but rarely at this depth and never with the same mineral mix."}]';
  static const _curated =
      '[{"type":"p","text":"Microbes living in warm ocean-floor fissures build their own food from dissolved minerals, without sunlight."},'
      '{"type":"p","text":"The vent chemistry resembles early oceans, so the finding matters beyond this field."}]';

  @override
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?>? params,
  ]) async {
    if (sql.contains('FROM kv')) return [];
    if (sql.contains('FROM presets')) {
      return [
        {
          'id': 1,
          'name': '六级练习',
          'config': '{"types":["choice","blank"],"count":5}',
        },
      ];
    }
    if (sql.contains('FROM plan_items')) {
      return sql.contains('WHERE') ? [{'articleId': 1}] : [{'articleId': 1}];
    }
    if (sql.contains('FROM question_sets s') && sql.contains('qcount')) {
      return [
        {'id': 7, 'articleId': 1, 'qcount': 5},
      ];
    }
    if (sql.contains('FROM question_sets s')) {
      return [
        {
          'id': 7,
          'createdAt': DateTime.now()
              .subtract(const Duration(days: 2))
              .millisecondsSinceEpoch,
          'label': '考前重做',
          'questionCount': 5,
          'attempts': 3,
          'correctAttempts': 2,
        },
        {
          'id': 6,
          'createdAt': DateTime.now()
              .subtract(const Duration(days: 5))
              .millisecondsSinceEpoch,
          'label': '细节题',
          'questionCount': 4,
          'attempts': 0,
          'correctAttempts': 0,
        },
      ];
    }
    if (sql.contains('FROM question_sets')) {
      return [{'articleId': 1}];
    }
    if (sql.contains('FROM questions q')) {
      return [
        {
          'id': 1,
          'setId': 1,
          'type': 'choice',
          'gradeMode': 'ai',
          'prompt':
              'According to the passage, what makes the vent microbes unusual?',
          'options':
              '["They build food from minerals without sunlight","They live above the surface","They migrate every season"]',
          'answers': '["They build food from minerals without sunlight"]',
          'analysis': '第一段直接说明它们不依赖阳光。',
          'sourceQuote':
              'build their own food from dissolved minerals, without sunlight',
        },
      ];
    }
    if (sql.contains('FROM questions')) {
      return [
        {
          'id': 1,
          'setId': 1,
          'type': 'choice',
          'gradeMode': 'ai',
          'prompt':
              'According to the passage, what makes the vent microbes unusual?',
          'options':
              '["They build food from minerals without sunlight","They live above the surface","They migrate every season"]',
          'answers': '["They build food from minerals without sunlight"]',
          'analysis': '第一段直接说明它们不依赖阳光。',
          'sourceQuote':
              'build their own food from dissolved minerals, without sunlight',
        },
      ];
    }
    if (sql.contains('FROM answers')) return [];
    if (sql.contains('FROM articles WHERE id IN')) {
      return [
        {
          'id': 1,
          'guid': 'g-1',
          'title': _title,
          'wordCount': 420,
          'hasCurated': 1,
        },
      ];
    }
    if (sql.contains('FROM articles')) {
      return [
        {
          'id': 1,
          'guid': 'g-1',
          'title': _title,
          'sourceUrl': 'https://example.com/vent',
          'html': '<p>body</p>',
          'blocks': _blocks,
          'curated_blocks': _curated,
          'wordCount': 420,
          'difficulty': 68,
        },
      ];
    }
    return [];
  }

  @override
  Future<int> insertReturnId(String sql, [List<Object?>? params]) async => 1;

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {}
}

class _ShotFeeds extends FeedsService {
  _ShotFeeds(this.rows)
      : super(FakeDb(), RssService(HttpService()), HttpService());

  final List<Map<String, dynamic>> rows;

  @override
  Future<List<Feed>> ensureFeeds() async => const [];

  @override
  Future<List<Feed>> listFeeds() async => const [];

  @override
  Future<List<Map<String, dynamic>>> loadItemsJoined(int cap, int offset) async =>
      rows;
}

class _ShotHabit extends HabitService {
  _ShotHabit() : super(FakeDb());

  @override
  Future<HabitState> getState() async => const HabitState(
        streak: 12,
        maxStreak: 21,
        total: 68,
        accuracy: 82,
        todayCount: 42,
        goal: 60,
        isTodayDone: false,
        brokenYesterday: false,
        badges: [],
        xpTotal: 1840,
        todayXp: 42,
        goalXp: 60,
        level: 4,
        levelFloor: 1500,
        levelCeil: 2100,
        questRead: 1,
        questVocab: 0,
        questQuiz: 0,
        questBonus: false,
        freezesAvailable: 1,
        weekXp: 310,
        lastWeekXp: 280,
        bestDayXp: 96,
        canRepair: false,
      );
}

class _ShotVocab extends VocabService {
  _ShotVocab()
      : super(FakeDb(), LlmService(HttpService(), AppConfigService()));

  static Map<String, dynamic> _row(
    String head,
    String zh,
    int occ,
    int sources,
    int dueInDays,
  ) =>
      {
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
      ];

  @override
  Future<int> dueCount() async => 3;
}

class _ShotWord extends WordService {
  _ShotWord()
      : super(
          FakeDb(),
          TranslateService(
            HttpService(),
            AppConfigService(),
            LlmService(HttpService(), AppConfigService()),
          ),
        );

  @override
  Future<String> lookup(String word, {String mode = 'en2zh'}) async =>
      '热液的；与热水有关的';
}

List<Map<String, dynamic>> _rows() {
  final now = DateTime.now().millisecondsSinceEpoch;
  return [
    {
      'id': 1,
      'feedId': 1,
      'guid': 'g1',
      'title': 'Deep-sea vents push the origin of life further back',
      'link': 'https://example.com/1',
      'preview': '',
      'pubDate': now - 12 * 60 * 1000,
      'fetchedAt': now,
      'sourceTitle': 'FeedOverview 科学',
      'sourceUrl': 'https://example.com/feeds/Science.xml',
      'sourceCat': 'Science',
      'difficulty': 68,
    },
    {
      'id': 2,
      'feedId': 2,
      'guid': 'g2',
      'title': 'Why old mechanical keyboards are popular again',
      'link': 'https://example.com/2',
      'preview': '',
      'pubDate': now - 3 * 3600 * 1000,
      'fetchedAt': now,
      'sourceTitle': 'My tech feed',
      'sourceUrl': 'https://example.com/feed.xml',
      'sourceCat': 'Tech',
      'sourceOrigin': 'custom',
      'difficulty': 52,
    },
    {
      'id': 3,
      'feedId': 3,
      'guid': 'g3',
      'title': 'A small-town library became a late-night refuge',
      'link': 'https://example.com/3',
      'preview': '',
      'pubDate': now - 30 * 3600 * 1000,
      'fetchedAt': now,
      'sourceTitle': '',
      'sourceUrl': 'local://imported',
      'sourceCat': '我的导入',
      'sourceOrigin': 'imported',
      'difficulty': 45,
    },
    {
      'id': 4,
      'feedId': 1,
      'guid': 'g4',
      'title': 'Cities are planting shade before they plant trees',
      'link': 'https://example.com/4',
      'preview': '',
      'pubDate': now - 2 * 24 * 3600 * 1000,
      'fetchedAt': now,
      'sourceTitle': 'FeedOverview 环境',
      'sourceUrl': 'https://example.com/feeds/Environment.xml',
      'sourceCat': 'Environment',
      'difficulty': 74,
    },
    {
      'id': 5,
      'feedId': 1,
      'guid': 'g5',
      'title': 'What a 19th-century diary tells us about attention',
      'link': 'https://example.com/5',
      'preview': '',
      'pubDate': now - 3 * 24 * 3600 * 1000,
      'fetchedAt': now,
      'sourceTitle': 'FeedOverview 思想文化',
      'sourceUrl': 'https://example.com/feeds/Ideas.xml',
      'sourceCat': 'Ideas',
      'difficulty': 62,
    },
    {
      'id': 6,
      'feedId': 1,
      'guid': 'g6',
      'title': 'A simple way to read a paper you disagree with',
      'link': 'https://example.com/6',
      'preview': '',
      'pubDate': now - 4 * 24 * 3600 * 1000,
      'fetchedAt': now,
      'sourceTitle': 'FeedOverview 英语学习',
      'sourceUrl': 'https://example.com/feeds/Learner.xml',
      'sourceCat': 'Learner',
      'difficulty': 50,
    },
  ];
}

ThemeData _theme(ThemeData base) => base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: 'Roboto',
        fontFamilyFallback: const ['CJK'],
      ),
    );

Widget _host(Widget home, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(V4Theme.light()),
      builder: (context, child) => DefaultTextStyle.merge(
        style: const TextStyle(
          fontFamily: 'Roboto',
          fontFamilyFallback: ['CJK'],
        ),
        child: child!,
      ),
      home: home,
    ),
  );
}

/// Tab bodies assume a Scaffold above them; the shell supplies it in the app.
class _TabHost extends StatelessWidget {
  const _TabHost(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.v4.page,
      body: SizedBox.expand(child: child),
    );
  }
}

class _WordCardHost extends StatefulWidget {
  const _WordCardHost();

  @override
  State<_WordCardHost> createState() => _WordCardHostState();
}

class _WordCardHostState extends State<_WordCardHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showWordCard(
        context,
        word: 'hydrothermal',
        sentence:
            'A team sampling warm fissures found microbes that build their own food.',
        articleGuid: 'g-1',
        articleTitle: 'Deep-sea vents push the origin of life further back',
        sourceLabel: 'FeedOverview 科学',
        paraIndex: 1,
        tokIndex: 4,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.v4.page,
      body: const SizedBox.expand(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadShotFonts);

  Future<void> shot(
    WidgetTester tester,
    String name,
    Widget home, {
    List<Override> overrides = const [],
    bool settle = true,
    Future<void> Function(WidgetTester)? before,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(824, 1830);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(home, overrides: overrides));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    if (settle) await tester.pump(const Duration(milliseconds: 300));
    if (before != null) await before(tester);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../docs/screenshots/$name.png'),
    );
  }

  final db = _ShotDb();

  testWidgets('01 home', (tester) async {
    await shot(
      tester,
      '01_home',
      const V4Shell(profile: V4Profile(completed: true)),
      overrides: [
        dbProvider.overrideWithValue(FakeDb()),
        feedsProvider.overrideWithValue(_ShotFeeds(_rows())),
        habitProvider.overrideWithValue(_ShotHabit()),
      ],
    );
  }, skip: !_enabled);

  testWidgets('02 reading', (tester) async {
    await shot(
      tester,
      '02_reading',
      const _TabHost(V4ReadingScreen(profile: V4Profile(completed: true))),
      overrides: [
        dbProvider.overrideWithValue(FakeDb()),
        feedsProvider.overrideWithValue(_ShotFeeds(_rows())),
      ],
    );
  }, skip: !_enabled);

  testWidgets('03 article', (tester) async {
    await shot(
      tester,
      '03_article',
      const V4ReaderScreen(articleId: 1),
      overrides: [dbProvider.overrideWithValue(db)],
    );
  }, skip: !_enabled);

  testWidgets('04 word card', (tester) async {
    await shot(
      tester,
      '04_wordcard',
      const _WordCardHost(),
      overrides: [
        dbProvider.overrideWithValue(FakeDb()),
        wordProvider.overrideWithValue(_ShotWord()),
        vocabProvider.overrideWithValue(_ShotVocab()),
      ],
      before: (tester) async {
        await tester.pumpAndSettle();
      },
    );
  }, skip: !_enabled);

  testWidgets('05 plan', (tester) async {
    await shot(
      tester,
      '05_plan',
      const V4PlanScreen(),
      overrides: [dbProvider.overrideWithValue(db)],
    );
  }, skip: !_enabled);

  testWidgets('06 vocab', (tester) async {
    await shot(
      tester,
      '06_vocab',
      const V4VocabScreen(),
      overrides: [
        dbProvider.overrideWithValue(FakeDb()),
        vocabProvider.overrideWithValue(_ShotVocab()),
      ],
    );
  }, skip: !_enabled);

  testWidgets('07 mine', (tester) async {
    await shot(
      tester,
      '07_mine',
      const _TabHost(V4MineScreen(profile: V4Profile(completed: true))),
      overrides: [dbProvider.overrideWithValue(FakeDb())],
    );
  }, skip: !_enabled);

  testWidgets('08 quiz', (tester) async {
    await shot(
      tester,
      '08_quiz',
      const V4QuizScreen(setId: 1),
      overrides: [dbProvider.overrideWithValue(db)],
    );
  }, skip: !_enabled);

  testWidgets('09 guide', (tester) async {
    await shot(tester, '09_guide', const V4GuideScreen());
  }, skip: !_enabled);
}
