import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/models/models.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/feeds_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/rss_service.dart';
import 'package:global_overview/v4/screens/reader_screen.dart';
import 'package:global_overview/v4/screens/reading_screen.dart';
import 'package:global_overview/v4/screens/today_screen.dart';
import 'package:global_overview/v4/services/onboarding_service.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:global_overview/v4/widgets/article_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_db.dart';

class _InsertDb extends FakeDb {
  int inserted = 0;
  @override
  Future<int> insertReturnId(String sql, [List<Object?>? params]) async {
    inserted++;
    return 42;
  }
}

class _FakeFeeds extends FeedsService {
  _FakeFeeds({
    this.rows = const [],
    this.captureId = 7,
    this.fresh = true,
    this.unusable = false,
    this.failCapture = false,
  }) : super(FakeDb(), RssService(HttpService()), HttpService());

  final List<Map<String, dynamic>> rows;
  final int captureId;
  final bool fresh;
  final bool unusable;
  final bool failCapture;
  int captureCalls = 0;
  bool lastForce = false;

  @override
  Future<List<Feed>> ensureFeeds() async => const [];

  @override
  Future<List<Feed>> listFeeds() async => const [];

  @override
  Future<List<Map<String, dynamic>>> loadItemsJoined(int cap, int offset) async =>
      rows;

  @override
  Future<bool> looksUnusable(int articleId) async => unusable;

  @override
  Future<({int id, bool fresh})> captureArticle(
    String guid,
    String link,
    String title, {
    bool force = false,
  }) async {
    captureCalls++;
    lastForce = force;
    if (failCapture) throw StateError('capture failed');
    return (id: captureId, fresh: fresh);
  }

  @override
  Future<({bool ok, int count, int failCount, String? error})> fetchFeedInto(
    Feed feed,
    bool replaceCache, {
    DateTime? deadline,
  }) async => (ok: true, count: 0, failCount: 0, error: null);
}

List<Map<String, dynamic>> _rows() {
  final now = DateTime.now().millisecondsSinceEpoch;
  return [
    {
      'id': 1,
      'feedId': 1,
      'guid': 'g1',
      'title': 'First article about science',
      'link': 'https://example.com/1',
      'preview': 'preview one',
      'pubDate': now - 60 * 1000,
      'fetchedAt': now,
      'sourceTitle': 'FeedOverview · 科学',
      'sourceUrl': 'https://example.com/feeds/Science.xml',
      'sourceCat': 'Science',
    },
    {
      'id': 2,
      'feedId': 2,
      'guid': 'g2',
      'title': 'Second article about tech',
      'link': 'https://example.com/2',
      'preview': 'preview two',
      'pubDate': now - 3 * 3600 * 1000,
      'fetchedAt': now,
      'sourceTitle': 'FeedOverview · 科技',
      'sourceUrl': 'https://example.com/feeds/Tech.xml',
      'sourceCat': 'Tech',
    },
    {
      'id': 3,
      'feedId': 1,
      'guid': 'g3',
      'title': 'Third article about culture',
      'link': 'https://example.com/3',
      'preview': 'preview three',
      'pubDate': now - 30 * 3600 * 1000,
      'fetchedAt': now,
      'sourceTitle': 'FeedOverview · 文化',
      'sourceUrl': 'https://example.com/feeds/Ideas.xml',
      'sourceCat': 'Ideas',
    },
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget host({
    required DbService db,
    required FeedsService feeds,
    required Widget child,
  }) {
    return ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db),
        feedsProvider.overrideWithValue(feeds),
      ],
      child: MaterialApp(
        theme: V4Theme.light(),
        home: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }

  Widget launcherHost(DbService db, FeedsService feeds, Map<String, dynamic> item) {
    return host(
      db: db,
      feeds: feeds,
      child: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => Center(
            child: TextButton(
              onPressed: () => openV4Article(context, ref, item),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('缺少 guid 时提示且不打开阅读器', (tester) async {
    final feeds = _FakeFeeds();
    await tester.pumpWidget(
      launcherHost(FakeDb(), feeds, {'title': 'No guid', 'link': ''}),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('这篇文章缺少稳定链接，暂时无法打开'), findsOneWidget);
    expect(find.byType(V4ReaderScreen), findsNothing);
    expect(feeds.captureCalls, 0);
  });

  testWidgets('FeedOverview 文章走精简正文入库并打开阅读器', (tester) async {
    final db = _InsertDb();
    await tester.pumpWidget(
      launcherHost(db, _FakeFeeds(), {
        'guid': 'guid-1',
        'title': 'Condensed article',
        'sourceUrl': 'https://none-ptr.github.io/FeedOverview/feeds/Tech.xml',
        'preview': '<p>Body paragraph that is long enough to be kept.</p>',
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(db.inserted, 1);
    expect(find.byType(V4ReaderScreen), findsOneWidget);
  });

  testWidgets('外站文章走抓取链路，正文不可用时强制重抓一次', (tester) async {
    final feeds = _FakeFeeds(fresh: false, unusable: true, captureId: 9);
    await tester.pumpWidget(
      launcherHost(FakeDb(), feeds, {
        'guid': 'guid-2',
        'title': 'External article',
        'sourceUrl': 'https://example.com/article',
        'link': 'https://example.com/article',
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(feeds.captureCalls, 2);
    expect(feeds.lastForce, isTrue);
    expect(find.byType(V4ReaderScreen), findsOneWidget);
  });

  testWidgets('抓取失败时关闭加载框并给出错误弹窗', (tester) async {
    final feeds = _FakeFeeds(failCapture: true);
    await tester.pumpWidget(
      launcherHost(FakeDb(), feeds, {
        'guid': 'guid-3',
        'title': 'Broken article',
        'sourceUrl': 'https://example.com/broken',
        'link': 'https://example.com/broken',
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('文章暂时打不开'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('文章暂时打不开'), findsNothing);
    expect(find.byType(V4ReaderScreen), findsNothing);
  });

  testWidgets('今日页在有数据时展示三条文章', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(
        db: FakeDb(),
        feeds: _FakeFeeds(rows: _rows()),
        child: const V4TodayScreen(
          profile: V4Profile(completed: true),
          onOpenReading: _noop,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('First article about science'), findsOneWidget);
    expect(find.text('Second article about tech'), findsOneWidget);
    expect(find.text('Third article about culture'), findsOneWidget);
    expect(find.text('暂时无法获取今日文章'), findsNothing);
  });

  testWidgets('今日页只保留三条去重后的文章', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rows = _rows();
    rows.add({...rows.first, 'id': 4});
    await tester.pumpWidget(
      host(
        db: FakeDb(),
        feeds: _FakeFeeds(rows: rows),
        child: const V4TodayScreen(
          profile: V4Profile(completed: true),
          onOpenReading: _noop,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('First article about science'), findsOneWidget);
    expect(find.text('Third article about culture'), findsOneWidget);
  });

  testWidgets('阅读页在有数据时展示文章并可切换分类', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(
        db: FakeDb(),
        feeds: _FakeFeeds(rows: _rows()),
        child: const V4ReadingScreen(profile: V4Profile(completed: true)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('First article about science'), findsOneWidget);
    expect(find.text('Second article about tech'), findsOneWidget);

    final techChip = find.byKey(const ValueKey('v4-category-科技'));
    expect(techChip, findsOneWidget);
    await tester.tap(techChip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Second article about tech'), findsOneWidget);
    expect(find.text('First article about science'), findsNothing);
  });

  testWidgets('阅读页可按难度筛选并搜索标题', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now().millisecondsSinceEpoch;
    Map<String, dynamic> row(int id, String title, int difficulty) => {
          'id': id,
          'guid': 'g$id',
          'title': title,
          'link': 'https://example.com/$id',
          'preview': '',
          'pubDate': now,
          'sourceTitle': 'FeedOverview 科学',
          'sourceCat': 'Science',
          'difficulty': difficulty,
        };
    await tester.pumpWidget(
      host(
        db: FakeDb(),
        feeds: _FakeFeeds(rows: [
          row(1, 'Advanced piece', 78),
          row(2, 'Keyboard history', 45),
          row(3, 'Middle piece', 62),
        ]),
        child: const V4ReadingScreen(profile: V4Profile(completed: true)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const ValueKey('v4-reading-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进阶').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.text('Advanced piece'), findsOneWidget);
    expect(find.text('Middle piece'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('v4-reading-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('v4-reading-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('v4-reading-search-field')),
      'keyboard',
    );
    await tester.pumpAndSettle();

    expect(find.text('Keyboard history'), findsOneWidget);
    expect(find.text('Advanced piece'), findsNothing);
  });

  testWidgets('阅读页标明本地导入与自定义源，并提供导入入口', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = [
      {
        'id': 1,
        'guid': 'g-local',
        'title': 'Pasted article',
        'link': '',
        'preview': '',
        'pubDate': now,
        'sourceTitle': '',
        'sourceCat': '我的导入',
        'sourceOrigin': 'imported',
      },
      {
        'id': 2,
        'guid': 'g-custom',
        'title': 'From custom feed',
        'link': 'https://example.com/custom',
        'preview': '',
        'pubDate': now,
        'sourceTitle': 'My feed',
        'sourceCat': '科技',
        'sourceOrigin': 'custom',
      },
    ];
    await tester.pumpWidget(
      host(
        db: FakeDb(),
        feeds: _FakeFeeds(rows: rows),
        child: const V4ReadingScreen(profile: V4Profile(completed: true)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('v4-reading-import')), findsOneWidget);
    expect(find.text('我的导入'), findsWidgets);
    expect(find.text('My feed（自定义）'), findsOneWidget);
  });
}


void _noop() {}
