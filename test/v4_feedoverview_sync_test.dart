import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/v4/services/feedoverview_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SyncDb extends DbService {
  final List<({String sql, List<Object?> params})> writes = [];

  @override
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?>? params,
  ]) async {
    if (sql.contains('FROM feeds')) return [{'id': 1}];
    if (sql.contains('FROM articles')) return [];
    return [];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {
    writes.add((sql: sql, params: params ?? const []));
  }

  @override
  Future<int> insertReturnId(String sql, [List<Object?>? params]) async {
    writes.add((sql: sql, params: params ?? const []));
    return 5;
  }
}

const _feedXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
  <item>
    <title>Tech story</title>
    <link>https://example.com/tech</link>
    <guid>tech-1</guid>
    <category>科技</category>
    <description><![CDATA[<p>Body of the tech story.</p>]]></description>
    <pubDate>Wed, 20 Nov 2026 08:00:00 GMT</pubDate>
  </item>
  <item>
    <title>Unknown category story</title>
    <link>https://example.com/other</link>
    <guid>other-1</guid>
    <category>神秘分类</category>
    <description><![CDATA[<p>Another body.</p>]]></description>
  </item>
  <item>
    <title></title>
    <guid>skip-me</guid>
  </item>
</channel></rss>
''';

http.Response _response(String body, [int status = 200]) => http.Response(
  body,
  status,
  headers: const {'content-type': 'text/xml; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  HttpService httpReturning(String body, {int status = 200}) => HttpService(
    client: MockClient((request) async => _response(body, status)),
  );

  test('sync 解析 RSS 并写入 feeds 与 feed_items', () async {
    final db = _SyncDb();
    final service = FeedOverviewService(db, httpReturning(_feedXml));

    final added = await service.sync();

    expect(added, 2);
    final feedWrites = db.writes.where((w) => w.sql.contains('INTO feeds')).toList();
    expect(feedWrites.length, 2);
    expect(
      feedWrites.map((w) => w.params[2]).toList(),
      ['Tech', 'Life'],
      reason: 'unknown categories fall back to Life',
    );

    final itemWrites = db.writes
        .where((w) => w.sql.contains('INTO feed_items'))
        .toList();
    expect(itemWrites.length, 2);
    expect(itemWrites.first.params[2], 'Tech story');
    expect(
      itemWrites.first.params[1],
      'tech-1',
      reason: 'guid is kept so the item stays stable across syncs',
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(FeedOverviewService.lastSyncKey), isNotNull);
  });

  test('sync 使用自建根地址拼接 feed.xml 与分类地址', () async {
    final db = _SyncDb();
    final requested = <String>[];
    final service = FeedOverviewService(
      db,
      HttpService(
        client: MockClient((request) async {
          requested.add(request.url.toString());
          return _response(_feedXml);
        }),
      ),
    );
    expect(
      await service.setRootUrl('https://mirror.example.com/FeedOverview'),
      isTrue,
    );

    await service.sync();

    expect(requested.single, 'https://mirror.example.com/FeedOverview/feed.xml');
    final feedUrl = db.writes.firstWhere(
      (w) => w.sql.contains('INTO feeds'),
    ).params[1];
    // The published category files are lower-case; Tech.xml 404s on Pages.
    expect(feedUrl, 'https://mirror.example.com/FeedOverview/feeds/tech.xml');
  });

  test('关闭加速后 syncIfNeeded 不发起请求', () async {
    final db = _SyncDb();
    var called = 0;
    final service = FeedOverviewService(
      db,
      HttpService(
        client: MockClient((request) async {
          called++;
          return _response(_feedXml);
        }),
      ),
    );
    await service.setEnabled(false);

    expect(await service.syncIfNeeded(force: true), 0);
    expect(called, 0);
  });

  test('15 分钟内重复调用不重新同步，force 时强制同步', () async {
    final db = _SyncDb();
    var called = 0;
    final service = FeedOverviewService(
      db,
      HttpService(
        client: MockClient((request) async {
          called++;
          return _response(_feedXml);
        }),
      ),
    );

    expect(await service.syncIfNeeded(), 2);
    expect(await service.syncIfNeeded(), 0);
    expect(called, 1);

    expect(await service.syncIfNeeded(force: true), 2);
    expect(called, 2);
  });

  test('captureArticle 首次写入并返回新 id', () async {
    final db = _SyncDb();
    final service = FeedOverviewService(db, httpReturning(''));

    final id = await service.captureArticle({
      'guid': 'tech-1',
      'link': 'https://example.com/tech',
      'title': 'Tech story',
      'preview': '<h2>Heading</h2><p>First paragraph.</p>',
    });

    expect(id, 5);
    final insert = db.writes.singleWhere((w) => w.sql.contains('INTO articles'));
    expect(insert.params[0], 'tech-1');
    expect(insert.params[3], contains('First paragraph'));
    expect(insert.params[5], contains('"type":"p"'));
  });

  test('captureArticle 遇到已有 guid 时更新而不是重复插入', () async {
    final db = _ExistingDb();
    final service = FeedOverviewService(db, httpReturning(''));

    final id = await service.captureArticle({
      'guid': 'tech-1',
      'link': 'https://example.com/tech',
      'title': 'Updated title',
      'preview': '<p>Updated body.</p>',
    });

    expect(id, 11);
    expect(db.writes.single.sql, contains('UPDATE articles'));
    expect(db.writes.single.params.first, 'Updated title');
  });

  test('正文为空时拒绝入库', () async {
    final service = FeedOverviewService(_SyncDb(), httpReturning(''));
    expect(
      () => service.captureArticle({
        'guid': 'empty',
        'title': 'Empty',
        'preview': '',
      }),
      throwsStateError,
    );
  });
}

class _ExistingDb extends _SyncDb {
  @override
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?>? params,
  ]) async {
    if (sql.contains('FROM articles')) return [{'id': 11}];
    return super.select(sql, params);
  }
}
