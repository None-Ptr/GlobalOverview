import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/feeds_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/rss_service.dart';
import 'package:global_overview/v4/services/import_service.dart';

class _Call {
  final String sql;
  final List<Object?> params;
  _Call(this.sql, this.params);
}

class _RecordingDb extends DbService {
  final calls = <_Call>[];
  bool feedExists = false;

  @override
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?>? params,
  ]) async {
    calls.add(_Call(sql, params ?? const []));
    if (sql.contains('FROM feeds WHERE url')) {
      return feedExists ? [{'id': 9}] : [];
    }
    return [];
  }

  @override
  Future<int> insertReturnId(String sql, [List<Object?>? params]) async {
    calls.add(_Call(sql, params ?? const []));
    return 11;
  }

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {
    calls.add(_Call(sql, params ?? const []));
  }
}

class FakeRss extends RssService {
  FakeRss() : super(HttpService());
}

void main() {
  test('粘贴正文生成文章、导入源和阅读列表条目', () async {
    final db = _RecordingDb()..feedExists = true;
    final svc = ImportService(db, HttpService());

    final id = await svc.importText(
      title: 'My notes',
      body: 'First paragraph with enough words to be a paragraph.\n\n'
          'Second paragraph with more words.',
    );

    expect(id, 11);
    final feed = db.calls.firstWhere(
      (c) => c.sql.contains('INSERT OR IGNORE INTO feeds'),
    );
    expect(feed.params[1], ImportService.localFeedUrl);
    expect(feed.params[4], 'imported');

    final article = db.calls.firstWhere(
      (c) => c.sql.contains('INSERT INTO articles'),
    );
    expect(article.params[0], startsWith('manual-'));
    expect(article.params[8], 'imported');
    expect(article.params[5], contains('"p"'));

    final item = db.calls.firstWhere(
      (c) => c.sql.contains('INSERT OR REPLACE INTO feed_items'),
    );
    expect(item.params[0], 9);
    expect(item.params[1], article.params[0]);
  });

  test('粘贴正文标题或内容为空时拒绝', () async {
    final svc = ImportService(_RecordingDb(), HttpService());
    await expectLater(
      svc.importText(title: '', body: 'some long body'),
      throwsA(isA<AppException>()),
    );
    await expectLater(
      svc.importText(title: 'Title', body: 'short'),
      throwsA(isA<AppException>()),
    );
  });

  test('网址导入只接受 http(s)', () async {
    final svc = ImportService(_RecordingDb(), HttpService());
    await expectLater(
      svc.importUrl(url: 'file:///tmp/a.html'),
      throwsA(isA<AppException>()),
    );
  });

  test('添加自定义 RSS 源写 origin=custom', () async {
    final db = _RecordingDb();
    final svc = FeedsService(db, FakeRss(), HttpService());
    final id = await svc.addCustomFeed(
      title: 'My feed',
      url: 'https://example.com/feed.xml',
      category: '科技',
    );

    expect(id, 11);
    final call = db.calls.firstWhere((c) => c.sql.contains('INSERT INTO feeds'));
    expect(call.params[1], 'https://example.com/feed.xml');
    expect(call.params[2], '科技');
    expect(call.params[4], 'custom');
  });

  test('自定义 RSS 源拒绝重复地址和非法地址', () async {
    final svc = FeedsService(
      _RecordingDb()..feedExists = true,
      FakeRss(),
      HttpService(),
    );
    await expectLater(
      svc.addCustomFeed(title: 'A', url: 'https://a.com/f.xml', category: '生活'),
      throwsA(isA<AppException>()),
    );
    final invalid = FeedsService(_RecordingDb(), FakeRss(), HttpService());
    await expectLater(
      invalid.addCustomFeed(title: 'A', url: 'not a url', category: '生活'),
      throwsA(isA<AppException>()),
    );
  });
}
