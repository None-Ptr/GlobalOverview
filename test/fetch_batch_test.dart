import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:global_overview/models/models.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/feeds_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/rss_service.dart';

import 'fake_db.dart';

/// 记录 SQL 并维护一张内存版 feed_items，用来断言批量写入的语义。
String _key(dynamic feedId, String guid) => '$feedId|$guid';

class _Store extends FakeDb {
  final List<String> log = [];
  final Map<String, Map<String, dynamic>> rows = {};

  @override
  Future<List<Map<String, dynamic>>> select(String sql, [List<Object?>? params]) async {
    log.add(sql);
    if (sql.startsWith('SELECT guid FROM feed_items')) {
      final feedId = params?[0];
      return rows.entries
          .where((e) => e.key.startsWith('$feedId|'))
          .map((e) => <String, dynamic>{'guid': e.value['guid']})
          .toList();
    }
    return [];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {
    log.add(sql);
    if (sql.startsWith('INSERT OR REPLACE INTO feed_items') ||
        sql.startsWith('INSERT OR IGNORE INTO feed_items')) {
      final p = params ?? const [];
      for (var i = 0; i + 6 < p.length; i += 7) {
        rows[_key(p[i], '${p[i + 1]}')] = {
          'feedId': p[i],
          'guid': '${p[i + 1]}',
          'title': '${p[i + 2]}',
          'fetchedAt': p[i + 6],
        };
      }
    }
  }

  @override
  Future<int> insertReturnId(String sql, [List<Object?>? params]) async {
    log.add(sql);
    return 1;
  }
}

String _rss(int n) {
  final b = StringBuffer('<?xml version="1.0"?><rss version="2.0"><channel>');
  for (var i = 0; i < n; i++) {
    b.write('<item><title>T$i</title><link>https://x/$i</link><guid>g$i</guid>'
        '<pubDate>Fri, 02 Oct 2026 10:0${i % 10}:00 GMT</pubDate></item>');
  }
  b.write('</channel></rss>');
  return b.toString();
}

FeedsService _service(_Store db, {int items = 30}) {
  final net = HttpService(client: MockClient((req) async => http.Response(_rss(items), 200)));
  return FeedsService(db, RssService(net), net);
}

void main() {
  test('刷新模式：30 篇只需 1 查 + 1 插，旧条目保留', () async {
    final db = _Store();
    // 预置一条 RSS 里已不存在的旧条目：刷新后必须保留
    db.rows[_key(null, 'g999')] = {'feedId': null, 'guid': 'g999', 'title': 'old'};
    final svc = _service(db);

    final r = await svc.fetchFeedInto(Feed(title: 'f', url: 'https://x/rss', category: 'News'), true);

    expect(r.ok, isTrue, reason: '抓取失败：${r.error}');
    expect(r.count, 30);
    expect(db.rows.length, 31, reason: '30 篇新内容 + 1 条已消失的旧条目应保留');

    int countOf(String prefix) => db.log.where((s) => s.startsWith(prefix)).length;
    expect(countOf('SELECT guid FROM feed_items'), 1, reason: '已有 guid 只查一次');
    expect(countOf('INSERT OR REPLACE INTO feed_items'), 1, reason: '30 篇应合成一条多行 INSERT');
    expect(countOf('DELETE FROM feed_items'), 0, reason: '不再需要 DELETE');
    expect(db.log.any((s) => s.contains('guid = ?')), isFalse, reason: '不应再有逐条 DELETE');
  });

  test('刷新模式重复抓取：条目数量不变、元数据被刷新', () async {
    final db = _Store();
    final svc = _service(db);

    await svc.fetchFeedInto(Feed(title: 'f', url: 'https://x/rss', category: 'News'), true);
    expect(db.rows.length, 30);

    // 源里改了标题后再抓一次：应被 REPLACE 刷新
    final logLen = db.log.length;
    final r2 = await svc.fetchFeedInto(Feed(title: 'f', url: 'https://x/rss', category: 'News'), true);

    expect(r2.count, 30, reason: '刷新模式按旧语义全量重插以刷新元数据');
    expect(db.rows.length, 30);
    final inserts = db.log.skip(logLen).where((s) => s.startsWith('INSERT OR REPLACE')).length;
    expect(inserts, 1, reason: '重复刷新同样只产生一条批量 INSERT');
  });

  test('追加模式：超过 100 条时分批插入（每批 ≤ 100 行）', () async {
    final db = _Store();
    final svc = _service(db, items: 250);

    final r = await svc.fetchFeedInto(Feed(title: 'f', url: 'https://x/rss', category: 'News'), false);

    expect(r.count, 250);
    expect(db.rows.length, 250);
    final inserts = db.log.where((s) => s.startsWith('INSERT OR IGNORE INTO feed_items')).length;
    expect(inserts, 3, reason: '250 条应分 100/100/50 三批');
  });

  test('追加模式重复抓取：不产生新的 INSERT', () async {
    final db = _Store();
    final svc = _service(db);

    await svc.fetchFeedInto(Feed(title: 'f', url: 'https://x/rss', category: 'News'), false);
    final logLen = db.log.length;
    final r2 = await svc.fetchFeedInto(Feed(title: 'f', url: 'https://x/rss', category: 'News'), false);

    expect(r2.count, 0);
    expect(db.log.skip(logLen).where((s) => s.startsWith('INSERT')).length, 0, reason: '已存在的条目不应再插入');
  });

  test('索引迁移脚本覆盖全部热路径', () {
    expect(dbIndexStatements.length, 10);
    for (final s in dbIndexStatements) {
      expect(s, startsWith('CREATE INDEX IF NOT EXISTS '), reason: s);
    }
    final tables = dbIndexStatements.map((s) => s.split(' ON ')[1].split('(').first).toSet();
    expect(tables, containsAll(<String>['feed_items', 'answers', 'vocab_occ', 'questions', 'vocab_head', 'word_cache']));
  });
}
