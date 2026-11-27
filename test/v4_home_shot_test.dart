import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/models/models.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/feeds_service.dart';
import 'package:global_overview/services/habit_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/rss_service.dart';
import 'package:global_overview/v4/screens/v4_shell.dart';
import 'package:global_overview/v4/services/onboarding_service.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_db.dart';
import 'shot_fonts.dart';

/// Renders the home tab to a PNG. Skipped by default so a font change on
/// another machine cannot fail the suite. Regenerate with:
/// `$env:HOME_SHOT=1; flutter test test/v4_home_shot_test.dart --update-goldens`
final _enabled = Platform.environment['HOME_SHOT'] == '1';
class _FakeFeeds extends FeedsService {
  _FakeFeeds(this.rows)
    : super(FakeDb(), RssService(HttpService()), HttpService());

  final List<Map<String, dynamic>> rows;

  @override
  Future<List<Feed>> ensureFeeds() async => const [];

  @override
  Future<List<Feed>> listFeeds() async => const [];

  @override
  Future<List<Map<String, dynamic>>> loadItemsJoined(int cap, int offset) async =>
      rows;

  @override
  Future<({bool ok, int count, int failCount, String? error})> fetchFeedInto(
    Feed feed,
    bool replaceCache, {
    DateTime? deadline,
  }) async => (ok: true, count: 0, failCount: 0, error: null);
}

class _FakeHabit extends HabitService {
  _FakeHabit() : super(FakeDb());

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

List<Map<String, dynamic>> _rows() {
  final now = DateTime.now().millisecondsSinceEpoch;
  return [
    {
      'id': 1,
      'feedId': 1,
      'guid': 'g1',
      'title': 'Hydrothermal vents yield microbes that push back the origin of life',
      'link': 'https://example.com/1',
      'preview': 'preview one',
      'pubDate': now - 12 * 60 * 1000,
      'fetchedAt': now,
      'sourceTitle': 'FeedOverview 路 绉戝',
      'sourceUrl': 'https://example.com/feeds/Science.xml',
      'sourceCat': 'Science',
    },
    {
      'id': 2,
      'feedId': 2,
      'guid': 'g2',
      'title': 'Why old mechanical keyboards are popular again: feel, sound, ritual',
      'link': 'https://example.com/2',
      'preview': 'preview two',
      'pubDate': now - 3 * 3600 * 1000,
      'fetchedAt': now,
      'sourceTitle': 'FeedOverview 路 绉戞妧',
      'sourceUrl': 'https://example.com/feeds/Tech.xml',
      'sourceCat': 'Tech',
    },
    {
      'id': 3,
      'feedId': 3,
      'guid': 'g3',
      'title': 'How a small-town library became a late-night refuge for readers',
      'link': 'https://example.com/3',
      'preview': 'preview three',
      'pubDate': now - 30 * 3600 * 1000,
      'fetchedAt': now,
      'sourceTitle': 'FeedOverview 路 鏂囧寲',
      'sourceUrl': 'https://example.com/feeds/Ideas.xml',
      'sourceCat': 'Ideas',
    },
  ];
}

Future<void> _loadFonts() => loadShotFonts();

ThemeData _theme(ThemeData base) => base.copyWith(
  textTheme: base.textTheme.apply(
    fontFamily: 'Roboto',
    fontFamilyFallback: const ['CJK'],
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadFonts);

  testWidgets('棣栭〉鎴浘', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(824, 1830);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(FakeDb()),
          feedsProvider.overrideWithValue(_FakeFeeds(_rows())),
          habitProvider.overrideWithValue(_FakeHabit()),
        ],
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
          home: const V4Shell(profile: V4Profile(completed: true)),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/home_light.png'),
    );
  }, skip: !_enabled);
}
