import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/models/models.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/curate_service.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/llm_service.dart';
import 'package:global_overview/v4/screens/quiz_screen.dart';
import 'package:global_overview/v4/screens/reader_screen.dart';
import 'package:global_overview/v4/services/image_cache.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:global_overview/v4/widgets/article_image.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

const _pixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

class _ReaderDb extends DbService {
  final List<String> writes = [];
  bool inPlan = false;

  @override
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?>? params,
  ]) async {
    if (sql.contains('FROM plan_items')) {
      return inPlan ? [{'articleId': 1}] : [];
    }
    if (sql.contains('FROM articles')) {
      return [
        {
          'guid': 'g-1',
          'title': 'A readable article',
          'sourceUrl': 'https://example.com/a',
          'html': '<p>body</p>',
          'blocks':
              '[{"type":"p","text":"First paragraph."},'
              '{"type":"img","src":"https://example.com/figure.png","alt":"A figure"},'
              '{"type":"p","text":"Second paragraph."}]',
          'wordCount': 120,
        },
      ];
    }
    return [];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {
    writes.add(sql);
    if (sql.startsWith('INSERT')) inPlan = true;
    if (sql.startsWith('DELETE')) inPlan = false;
  }
}

class _LongDb extends _ReaderDb {
  @override
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?>? params,
  ]) async {
    if (sql.contains('FROM articles')) {
      final blocks = [
        for (var i = 0; i < 30; i++)
          '{"type":"p","text":"Paragraph $i of a long article that keeps the '
              'page scrolling for a while."}',
      ].join(',');
      return [
        {
          'guid': 'g-long',
          'title': 'A long article',
          'sourceUrl': 'https://example.com/long',
          'html': '<p>body</p>',
          'blocks': '[$blocks]',
          'wordCount': 600,
        },
      ];
    }
    return super.select(sql, params);
  }
}

class _ReaderConfig extends AppConfigService {
  final List<Map<String, double?>> writes = [];

  @override
  Future<void> setReader({
    double? fontSize,
    double? lineHeight,
    String? transEngine,
  }) async {
    writes.add({'fontSize': fontSize, 'lineHeight': lineHeight});
  }
}

class _SetsDb extends _ReaderDb {
  String firstLabel = '考前重做';

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {
    if (sql.startsWith('UPDATE question_sets') && params != null) {
      firstLabel = '${params.first ?? ''}';
    }
    await super.execute(sql, params);
  }

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
          'label': firstLabel,
        },
        {
          'id': 6,
          'createdAt': DateTime(2026, 11, 24, 9, 5).millisecondsSinceEpoch,
          'questionCount': 3,
          'attempts': 0,
          'correctAttempts': null,
        },
      ];
    }
    return super.select(sql, params);
  }
}

class _FakeImages extends V4ImageCache {
  _FakeImages(this.file) : super(HttpService());

  final File? file;

  @override
  Future<File?> resolve(String url) async => file;
}

/// An article that already carries a generated version.
class _CuratedDb extends _ReaderDb {
  String? curated =
      '[{"type":"p","text":"Short first."},{"type":"p","text":"Short second."}]';

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {
    if (sql.startsWith('UPDATE articles SET curated_blocks')) {
      curated = params?.first as String?;
    }
    await super.execute(sql, params);
  }

  @override
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?>? params,
  ]) async {
    if (sql.contains('FROM articles')) {
      return [
        {
          'guid': 'g-curated',
          'title': 'A readable article',
          'sourceUrl': 'https://example.com/a',
          'html': '<p>body</p>',
          'blocks':
              '[{"type":"p","text":"Original first paragraph."},'
              '{"type":"p","text":"Original second paragraph."}]',
          'curated_blocks': curated,
          'wordCount': 120,
        },
      ];
    }
    return super.select(sql, params);
  }
}

class _FakeCurate extends CurateService {
  _FakeCurate() : super(LlmService(HttpService(), AppConfigService()));

  @override
  Future<List<ArticleBlock>> curate(
    List<ArticleBlock> blocks, {
    String? focus,
  }) async => [ArticleBlock(type: 'p', text: 'Generated short.')];
}

Widget _app(
  DbService db, {
  AppConfigService? config,
  V4ImageCache? images,
  CurateService? curate,
}) {
  return ProviderScope(
    overrides: [
      dbProvider.overrideWithValue(db),
      if (config != null) appConfigProvider.overrideWith((ref) => config),
      if (curate != null) curateProvider.overrideWithValue(curate),
      imageCacheProvider.overrideWith((ref) => images ?? _FakeImages(null)),
    ],
    child: MaterialApp(
      theme: V4Theme.light(),
      home: const V4ReaderScreen(articleId: 1),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('V4 阅读器渲染标题、字数与正文', (tester) async {
    await tester.pumpWidget(_app(_ReaderDb()));
    await _settle(tester);

    expect(find.text('A readable article'), findsOneWidget);
    expect(find.text('120 词'), findsOneWidget);
    expect(find.text('约 1 分钟'), findsOneWidget);
    expect(find.text('First paragraph.'), findsOneWidget);
    expect(find.text('打开原文'), findsOneWidget);
    expect(find.byType(V4ArticleImage), findsOneWidget);
  });

  testWidgets('正文段落带边栏编号，首段前言不编号', (tester) async {
    await tester.pumpWidget(_app(_ReaderDb()));
    await _settle(tester);

    expect(find.text('Why it is here:'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('00'), findsNothing);
  });

  testWidgets('文末列出这篇文章的历次题集，点开旧题集', (tester) async {
    await tester.pumpWidget(_app(_SetsDb()));
    await _settle(tester);

    expect(find.text('题集记录'), findsOneWidget);
    expect(find.text('11月25日 14:32'), findsOneWidget);
    expect(find.text('5 题  作答 3 次  正确 2 次'), findsOneWidget);
    expect(find.text('考前重做'), findsOneWidget);
    expect(find.text('11月24日 09:05'), findsOneWidget);
    expect(find.text('未作答'), findsOneWidget);

    await tester.ensureVisible(find.text('11月25日 14:32'));
    await _settle(tester);
    await tester.tap(find.text('11月25日 14:32'));
    await _settle(tester);
    expect(find.byType(V4QuizScreen), findsOneWidget);
  });

  testWidgets('长按题集可改用途标签并立即刷新', (tester) async {
    final db = _SetsDb();
    await tester.pumpWidget(_app(db));
    await _settle(tester);
    await tester.ensureVisible(find.text('11月25日 14:32'));
    await _settle(tester);

    await tester.longPress(find.text('11月25日 14:32'));
    await tester.pumpAndSettle();
    expect(find.text('用途标签'), findsOneWidget);

    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, '考前重做');

    await tester.enterText(field, '错题重做');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('错题重做'), findsOneWidget);
    expect(
      db.writes.any((sql) => sql.startsWith('UPDATE question_sets')),
      isTrue,
    );
  });

  testWidgets('缓存命中时把配图渲染成图片', (tester) async {
    final file = File(
      Directory.systemTemp.path + Platform.pathSeparator + 'v4_reader_pixel.png',
    );
    await tester.runAsync(() async {
      await file.writeAsBytes(base64Decode(_pixelPng));
    });

    await tester.pumpWidget(_app(_ReaderDb(), images: _FakeImages(file)));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('阅读器可以把文章加入精读单，再点一次移出', (tester) async {
    final db = _ReaderDb();
    await tester.pumpWidget(_app(db));
    await _settle(tester);

    await tester.tap(find.byTooltip('加入精读单'));
    await _settle(tester);

    expect(db.writes.any((sql) => sql.contains('INSERT OR REPLACE INTO plan_items')), isTrue);
    expect(find.byTooltip('移出精读单'), findsOneWidget);
    expect(find.text('已加入精读单'), findsOneWidget);

    await tester.tap(find.byTooltip('移出精读单'));
    await _settle(tester);

    expect(db.writes.any((sql) => sql.contains('DELETE FROM plan_items')), isTrue);
    expect(find.byTooltip('加入精读单'), findsOneWidget);
  });

  testWidgets('读完后记一笔见闻，并换成已记录状态', (tester) async {
    final db = _ReaderDb();
    await tester.pumpWidget(_app(db));
    await _settle(tester);

    expect(find.text('读完了'), findsOneWidget);

    await tester.tap(find.text('读完了'));
    await _settle(tester);

    expect(db.writes.any((sql) => sql.contains('INTO kv')), isTrue);
    expect(find.textContaining('+30 见闻'), findsOneWidget);
    expect(find.text('读完了'), findsNothing);
  });

  testWidgets('阅读设置可以改字号与行距，并写入配置', (tester) async {
    final config = _ReaderConfig();
    await tester.pumpWidget(_app(_ReaderDb(), config: config));
    await _settle(tester);

    await tester.tap(find.byTooltip('阅读设置'));
    await tester.pumpAndSettle();

    expect(find.text('阅读设置'), findsOneWidget);
    expect(tester.widget<TStepper>(find.byType(TStepper)).value, 18);

    await tester.tap(find.byIcon(TIcons.plus));
    await tester.pumpAndSettle();
    expect(tester.widget<TStepper>(find.byType(TStepper)).value, 20);

    await tester.tap(find.text('宽松'));
    await tester.pumpAndSettle();

    expect(config.writes.any((w) => w['fontSize'] == 20), isTrue);
    expect(config.writes.any((w) => w['lineHeight'] == 2.1), isTrue);
  });

  testWidgets('有精选版时默认显示精选，可切回原文', (tester) async {
    await tester.pumpWidget(_app(_CuratedDb()));
    await _settle(tester);

    expect(find.text('AI 精选'), findsOneWidget);
    expect(find.text('Short first.'), findsOneWidget);
    expect(find.text('Original first paragraph.'), findsNothing);
    expect(find.text('4 词'), findsOneWidget);

    expect(find.text('原文'), findsOneWidget);
    await tester.tap(find.text('原文'));
    await tester.pump();

    expect(find.text('Original first paragraph.'), findsOneWidget);
    expect(find.text('Short first.'), findsNothing);
    expect(find.text('120 词'), findsOneWidget);
  });

  testWidgets('菜单可以生成精选版并写库', (tester) async {
    final db = _CuratedDb()..curated = null;
    await tester.pumpWidget(_app(db, curate: _FakeCurate()));
    await _settle(tester);

    expect(find.text('Short first.'), findsNothing);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI 精选'));
    await tester.pumpAndSettle();

    expect(find.text('Generated short.'), findsOneWidget);
    expect(
      db.writes.any((sql) => sql.startsWith('UPDATE articles SET curated_blocks')),
      isTrue,
    );
  });

  testWidgets('向下阅读时顶栏收起，向上回看时回来', (tester) async {
    await tester.pumpWidget(_app(_LongDb()));
    await _settle(tester);

    final expanded = tester.getTopLeft(find.byType(ListView)).dy;

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    final collapsed = tester.getTopLeft(find.byType(ListView)).dy;
    expect(collapsed, lessThan(expanded));

    await tester.drag(find.byType(ListView), const Offset(0, 80));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(ListView)).dy, expanded);
  });
}
