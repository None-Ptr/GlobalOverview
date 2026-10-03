import 'dart:convert';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/rss_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/extract_service.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/models/models.dart';
import 'package:global_overview/services/feeds_data.dart';

class FeedsService {
  final DbService _db;
  final RssService _rss;
  final HttpService _http;
  FeedsService(this._db, this._rss, this._http);

  /// 批量 SQL 的每批行数：feed_items 每行 7 个参数，100 行 = 700 个绑定参数，
  /// 远低于 SQLite 旧版 999 的单语句上限。
  static const _sqlChunk = 100;

  static const minPlainChars = 300;

  static const blockedMarkers = <String>[
    'just a moment',
    'attention required',
    'access denied',
    'enable javascript',
    '403 forbidden',
    'please log in',
    'subscribe to continue',
    'checking your browser',
    'ddos protection',
  ];

  Future<List<Feed>> listFeeds() async {
    final rows = await _db.select('SELECT * FROM feeds ORDER BY addedAt DESC');
    return rows.map((e) => Feed.fromMap(e)).toList();
  }

  Future<void> removeFeed(int id) async {
    await _db.execute('DELETE FROM feeds WHERE id = ?', [id]);
    await _db.execute('DELETE FROM feed_items WHERE feedId = ?', [id]);
  }

  Future<List<FeedItem>> items({int? feedId, int limit = 50}) async {
    final sql = feedId == null
        ? 'SELECT * FROM feed_items ORDER BY pubDate DESC LIMIT ?'
        : 'SELECT * FROM feed_items WHERE feedId = ? ORDER BY pubDate DESC LIMIT ?';
    final args = feedId == null ? [limit] : [feedId, limit];
    final rows = await _db.select(sql, args);
    return rows.map((e) => FeedItem.fromMap(e)).toList();
  }

  Future<({int id, bool fresh})> captureArticle(String guid, String link, String title, {bool force = false}) async {
    final exist = await _db.select('SELECT id FROM articles WHERE guid = ?', [guid]);
    final oldId = exist.isEmpty ? null : exist.first['id'] as int;
    if (oldId != null && !force) return (id: oldId, fresh: false);
    final html = await _http.getText(link, retry: RetryPolicy.manual);
    final ex = ExtractService().extract(html, url: link);
    _guard(ex, link);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (oldId != null) {
      await _db.execute(
        'UPDATE articles SET title=?, author=?, sourceUrl=?, html=?, plainText=?, blocks=?, wordCount=?, capturedAt=? WHERE id=?',
        [ex.title ?? title, ex.author, link, html, ex.plainText, jsonEncode(ex.blocks.map((b) => b.toJson()).toList()), ex.wordCount, now, oldId],
      );
      return (id: oldId, fresh: true);
    }
    final id = await _db.insertReturnId(
      'INSERT INTO articles (guid, title, author, sourceUrl, html, plainText, blocks, wordCount, capturedAt) VALUES (?,?,?,?,?,?,?,?,?)',
      [guid, ex.title ?? title, ex.author, link, html, ex.plainText, jsonEncode(ex.blocks.map((b) => b.toJson()).toList()), ex.wordCount, now],
    );
    return (id: id, fresh: true);
  }

  /// 早于抓取守卫入库的历史数据：正文过短或缺失，视为不可用。
  Future<bool> looksUnusable(int articleId) async {
    final rows = await _db.select('SELECT wordCount, plainText FROM articles WHERE id = ?', [articleId]);
    if (rows.isEmpty) return false;
    final words = (rows.first['wordCount'] as int?) ?? 0;
    final plain = (rows.first['plainText'] as String?) ?? '';
    return words < 20 || plain.trim().length < minPlainChars;
  }

  /// 抓取成功判定：状态码由 HttpService把关，这里只管正文质量。
  void _guard(ExtractResult ex, String link) {
    final text = ex.plainText.trim();
    if (text.isEmpty || !ex.blocks.any((b) => b.type == 'p' && (b.text ?? '').trim().isNotEmpty)) {
      throw AppException('emptyArticle', '没有抓到正文', detail: link);
    }
    if (text.length < minPlainChars) {
      throw AppException('tooShort', '正文过短（${text.length} 字），可能是付费墙或错误页', detail: link);
    }
    final lower = text.toLowerCase();
    for (final marker in blockedMarkers) {
      if (lower.contains(marker)) {
        throw AppException('blocked', '抓到的是拦截页而不是正文', detail: '$link · $marker');
      }
    }
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
  Future<({bool ok, int count, int failCount, String? error})> fetchFeedInto(
    Feed feed,
    bool replaceCache, {
    DateTime? deadline,
  }) async {
    try {
      final items = await _rss.fetch(feed.url!, retry: RetryPolicy.until(deadline));
      final list = items.where((it) => it.title.trim().isNotEmpty).toList();
      if (list.isEmpty) {
        await _resetFail(feed);
        return (ok: true, count: 0, failCount: 0, error: null);
      }
      // 一次查出该源已有的 guid（走 UNIQUE(feedId, guid) 前缀索引），
      // 取代旧的「每篇一次 SELECT + 一次 INSERT + 一次 DELETE」的 N+1 写法
      // （30 篇 = 90 次 round-trip，14 个源一次刷新 ≈ 1260 次平台通道往返）。
      final existing = <String>{
        for (final r in await _db.select('SELECT guid FROM feed_items WHERE feedId = ?', [feed.id])) '${r['guid']}',
      };
      final fresh = list.where((it) => !existing.contains(it.guid)).toList();

      // 刷新模式：INSERT OR REPLACE 全量重插（旧实现是逐条 DELETE 后再逐条 INSERT，
      // 目的是刷新标题/预览/时间；feed 里已消失的旧条目两种写法都会保留）。
      // 追加模式：只补新条目。
      final toInsert = replaceCache ? list : fresh;
      final verb = replaceCache ? 'INSERT OR REPLACE' : 'INSERT OR IGNORE';
      var added = 0;
      for (var i = 0; i < toInsert.length; i += _sqlChunk) {
        final chunk = toInsert.skip(i).take(_sqlChunk).toList();
        final ph = chunk.map((_) => '(?,?,?,?,?,?,?)').join(',');
        final values = <Object?>[];
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final it in chunk) {
          values.addAll([feed.id, it.guid, it.title, it.link, it.preview, it.pubDate, now]);
        }
        await _db.execute(
          '$verb INTO feed_items (feedId, guid, title, link, preview, pubDate, fetchedAt) VALUES $ph',
          values,
        );
        added += chunk.length;
      }
      await _resetFail(feed);
      return (ok: true, count: added, failCount: 0, error: null);
    } catch (e) {
      final n = await _bumpFail(feed);
      return (ok: false, count: 0, failCount: n, error: errText(e));
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
