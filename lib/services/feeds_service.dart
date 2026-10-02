import 'dart:convert';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/rss_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/extract_service.dart';
import 'package:global_overview/models/models.dart';
import 'package:global_overview/services/feeds_data.dart';

class FeedsService {
  final DbService _db;
  final RssService _rss;
  final HttpService _http;
  FeedsService(this._db, this._rss, this._http);

  Future<void> addFeed(String url, String title, String category) async {
    await _db.execute('INSERT OR IGNORE INTO feeds (title, url, category, addedAt) VALUES (?,?,?,?)',
        [title, url, category, DateTime.now().millisecondsSinceEpoch]);
    final rows = await _db.select('SELECT id FROM feeds WHERE url = ?', [url]);
    if (rows.isNotEmpty) {
      await _db.execute('UPDATE feeds SET title = ?, category = ? WHERE id = ?', [title, category, rows.first['id']]);
    }
  }

  Future<List<Feed>> listFeeds() async {
    final rows = await _db.select('SELECT * FROM feeds ORDER BY addedAt DESC');
    return rows.map((e) => Feed.fromMap(e)).toList();
  }

  Future<void> removeFeed(int id) async {
    await _db.execute('DELETE FROM feeds WHERE id = ?', [id]);
    await _db.execute('DELETE FROM feed_items WHERE feedId = ?', [id]);
  }

  Future<int> fetchAll() async {
    final feeds = await listFeeds();
    var added = 0;
    for (final f in feeds) {
      try {
        final items = await _rss.fetch(f.url!);
        for (final it in items) {
          final exist = await _db.select('SELECT id FROM feed_items WHERE feedId = ? AND guid = ?', [f.id, it.guid]);
          if (exist.isEmpty) {
            await _db.execute(
                'INSERT INTO feed_items (feedId, guid, title, link, preview, pubDate, fetchedAt) VALUES (?,?,?,?,?,?,?)',
                [f.id, it.guid, it.title, it.link, it.preview, it.pubDate, DateTime.now().millisecondsSinceEpoch]);
            added++;
          }
        }
      } catch (_) {
        await _db.execute('UPDATE feeds SET failCount = COALESCE(failCount,0) + 1 WHERE id = ?', [f.id]);
      }
    }
    return added;
  }

  Future<List<FeedItem>> items({int? feedId, int limit = 50}) async {
    final sql = feedId == null
        ? 'SELECT * FROM feed_items ORDER BY pubDate DESC LIMIT ?'
        : 'SELECT * FROM feed_items WHERE feedId = ? ORDER BY pubDate DESC LIMIT ?';
    final args = feedId == null ? [limit] : [feedId, limit];
    final rows = await _db.select(sql, args);
    return rows.map((e) => FeedItem.fromMap(e)).toList();
  }

  Future<int> captureArticle(String guid, String link, String title) async {
    final exist = await _db.select('SELECT id FROM articles WHERE guid = ?', [guid]);
    if (exist.isNotEmpty) return exist.first['id'] as int;
    final html = await _http.getText(link);
    final ex = ExtractService().extract(html, url: link);
    final id = await _db.insertReturnId(
        'INSERT INTO articles (guid, title, author, sourceUrl, html, plainText, blocks, wordCount, capturedAt) VALUES (?,?,?,?,?,?,?,?,?)',
        [guid, ex.title ?? title, ex.author, link, html, ex.plainText, jsonEncode(ex.blocks.map((b) => b.toJson()).toList()), ex.wordCount, DateTime.now().millisecondsSinceEpoch]);
    return id;
  }

  // ================= 阅读页所需（对齐 reading.vue） =================

  /// 首次启动批量写入默认订阅源，并清理标题/URL 为空的脏数据；返回全部订阅源。
  Future<List<Feed>> ensureFeeds() async {
    final cnt = await _db.select('SELECT COUNT(*) AS c FROM feeds');
    final empty = cnt.isEmpty || (cnt.first['c'] as int? ?? 0) == 0;
    if (empty) {
      for (final f in defaultFeeds) {
        await _db.execute('INSERT OR IGNORE INTO feeds (title, url, category, addedAt) VALUES (?,?,?,?)',
            [f.title, f.url, f.category, DateTime.now().millisecondsSinceEpoch]);
      }
    }
    await _db.execute("DELETE FROM feeds WHERE title IS NULL OR title = '' OR url IS NULL OR url = ''");
    return listFeeds();
  }

  /// 聚合全部订阅源的已抓取文章（含来源信息），按 pubDate 倒序分页。
  Future<List<Map<String, dynamic>>> loadItemsJoined(int cap, int offset) async {
    return _db.select(
      'SELECT i.id, i.feedId, i.guid, i.title, i.link, i.preview, i.pubDate, i.fetchedAt, '
      'f.title AS sourceTitle, f.url AS sourceUrl, f.category AS sourceCat '
      'FROM feed_items i LEFT JOIN feeds f ON f.id = i.feedId '
      'ORDER BY i.pubDate DESC LIMIT ? OFFSET ?',
      [cap, offset],
    );
  }

  /// 抓取并入库单个源。返回 (ok, count, failCount)。
  Future<({bool ok, int count, int failCount})> fetchFeedInto(Feed feed, bool replaceCache) async {
    try {
      final items = await _rss.fetch(feed.url!);
      final list = items.where((it) => it.title.trim().isNotEmpty).toList();
      if (list.isEmpty) {
        await _resetFail(feed);
        return (ok: true, count: 0, failCount: 0);
      }
      final guids = list.map((e) => e.guid).toList();
      if (replaceCache) {
        for (final g in guids) {
          await _db.execute('DELETE FROM feed_items WHERE feedId = ? AND guid = ?', [feed.id, g]);
        }
      }
      var added = 0;
      for (final it in list) {
        final exist = await _db.select('SELECT id FROM feed_items WHERE feedId = ? AND guid = ?', [feed.id, it.guid]);
        if (exist.isNotEmpty) continue;
        await _db.execute(
            'INSERT OR IGNORE INTO feed_items (feedId, guid, title, link, preview, pubDate, fetchedAt) VALUES (?,?,?,?,?,?,?)',
            [feed.id, it.guid, it.title, it.link, it.preview, it.pubDate, DateTime.now().millisecondsSinceEpoch]);
        added++;
      }
      await _resetFail(feed);
      return (ok: true, count: added, failCount: 0);
    } catch (_) {
      final n = await _bumpFail(feed);
      return (ok: false, count: 0, failCount: n);
    }
  }

  Future<void> _resetFail(Feed feed) async {
    if (feed.id == null) return;
    try {
      await _db.execute('UPDATE feeds SET failCount = 0 WHERE id = ?', [feed.id]);
    } catch (_) {}
  }

  Future<int> _bumpFail(Feed feed) async {
    try {
      if (feed.id == null) return 0;
      final rows = await _db.select('SELECT failCount FROM feeds WHERE id = ?', [feed.id]);
      final cur = rows.isEmpty ? 0 : (rows.first['failCount'] as int? ?? 0);
      final next = cur + 1;
      await _db.execute('UPDATE feeds SET failCount = ? WHERE id = ?', [next, feed.id]);
      return next;
    } catch (_) {
      return 0;
    }
  }

  Future<void> subscribe(String title, String url, String category) async {
    await _db.execute('INSERT OR IGNORE INTO feeds (title, url, category, addedAt) VALUES (?,?,?,?)', [title, url, category, DateTime.now().millisecondsSinceEpoch]);
  }

  Future<void> unsubscribe(Feed feed) async {
    if (feed.id != null) await _db.execute('DELETE FROM feed_items WHERE feedId = ?', [feed.id]);
    await _db.execute('DELETE FROM feeds WHERE url = ?', [feed.url]);
  }

  Future<Map<String, bool>> loadPlanning() async {
    final out = <String, bool>{};
    try {
      final rows = await _db.select('SELECT a.guid FROM plan_items p JOIN articles a ON a.id = p.articleId');
      for (final r in rows) {
        out[r['guid'] as String] = true;
      }
    } catch (_) {}
    return out;
  }

  Future<int?> articleIdByGuid(String guid) async {
    final rows = await _db.select('SELECT id FROM articles WHERE guid = ?', [guid]);
    return rows.isEmpty ? null : rows.first['id'] as int?;
  }

  Future<void> addPlan(int articleId) async {
    await _db.execute('INSERT OR IGNORE INTO plan_items (articleId, addedAt) VALUES (?, ?)', [articleId, DateTime.now().millisecondsSinceEpoch]);
  }

  Future<void> removePlan(int articleId) async {
    await _db.execute('DELETE FROM plan_items WHERE articleId = ?', [articleId]);
  }
}
