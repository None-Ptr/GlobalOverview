import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

class FeedOverviewService {
  static const baseUrl = 'https://none-ptr.github.io/FeedOverview/';
  static const enabledKey = 'v4_feedoverview_enabled';
  static const lastSyncKey = 'v4_feedoverview_last_sync';
  static const rootUrlKey = 'v4_feedoverview_root_url';
  static const sourceTitle = 'FeedOverview';

  static const categories = <String, String>{
    '新闻': 'News',
    '科学': 'Science',
    '健康': 'Health',
    '科技': 'Tech',
    '商业': 'Business',
    '环境': 'Environment',
    '食物': 'Food',
    '艺术': 'Art',
    '设计': 'Design',
    '书籍文学': 'Books',
    '文化': 'Ideas',
    '英语学习': 'Learner',
    '体育': 'Sports',
    '旅行': 'Travel',
    '教育': 'Education',
    '政策智库': 'Policy',
    '生活': 'Life',
  };

  final DbService _db;
  final HttpService _http;
  FeedOverviewService(this._db, this._http);

  Future<bool> enabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledKey) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, value);
  }

  /// Accepts only an HTTPS directory root and normalizes the trailing slash.
  static String? normalizeRootUrl(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    if (uri.hasQuery || uri.hasFragment) return null;
    final path = uri.path.isEmpty
        ? '/'
        : (uri.path.endsWith('/') ? uri.path : uri.path + '/');
    final port = uri.hasPort ? ':' + uri.port.toString() : '';
    return 'https://' + uri.host + port + path;
  }

  Future<String> rootUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(rootUrlKey);
    final normalized = raw == null ? null : normalizeRootUrl(raw);
    return normalized ?? baseUrl;
  }

  Future<bool> setRootUrl(String raw) async {
    final normalized = normalizeRootUrl(raw);
    if (normalized == null) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(rootUrlKey, normalized);
    return true;
  }

  Future<void> clearRootUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(rootUrlKey);
  }

  Future<DateTime?> lastSync() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(lastSyncKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<int> syncIfNeeded({bool force = false}) async {
    if (!await enabled()) return 0;
    final previous = await lastSync();
    if (!force &&
        previous != null &&
        DateTime.now().difference(previous) < const Duration(minutes: 15)) {
      return 0;
    }
    return sync();
  }

  /// Category files on the site are lower-case (feeds/news.xml); the
  /// category key is not ('News'). GitHub Pages is case-sensitive, so the
  /// key has to be folded before it becomes a path.
  static String categoryFeedUrl(String root, String key) =>
      root + 'feeds/' + key.toLowerCase() + '.xml';

  /// Rewrites only the file name, so a self-hosted root keeps its casing.
  static String canonicalFeedUrl(String url) => url.replaceFirstMapped(
        RegExp(r'/feeds/([^/]+)\.xml$'),
        (m) => '/feeds/${m.group(1)!.toLowerCase()}.xml',
      );

  /// Older builds stored feeds/News.xml, which 404s. Fix the rows in place
  /// so the items already cached under them stay attached.
  Future<void> repairFeedUrls(String root) async {
    final rows = await _db.select(
      'SELECT id, url FROM feeds WHERE url LIKE ?',
      [root + 'feeds/%.xml'],
    );
    for (final row in rows) {
      final id = row['id'] as int;
      final url = row['url'] as String? ?? '';
      final fixed = canonicalFeedUrl(url);
      if (fixed == url) continue;
      try {
        await _db.execute('UPDATE feeds SET url = ? WHERE id = ?', [fixed, id]);
      } catch (_) {
        // A lower-case row already exists: fold this one into it.
        final target = await _db.select('SELECT id FROM feeds WHERE url = ?', [
          fixed,
        ]);
        if (target.isEmpty) continue;
        final targetId = target.first['id'] as int;
        await _db.execute(
          'UPDATE OR IGNORE feed_items SET feedId = ? WHERE feedId = ?',
          [targetId, id],
        );
        await _db.execute('DELETE FROM feed_items WHERE feedId = ?', [id]);
        await _db.execute('DELETE FROM feeds WHERE id = ?', [id]);
      }
    }
  }

  Future<int> sync() async {
    final root = await rootUrl();
    await repairFeedUrls(root);
    final text = await _http.getText(
      root + 'feed.xml',
      retry: RetryPolicy.manual,
    );
    final doc = XmlDocument.parse(text);
    final items = doc.findAllElements('item').take(80).toList();
    final now = DateTime.now().millisecondsSinceEpoch;
    var added = 0;

    for (final item in items) {
      String value(String name) {
        final node = item.findElements(name).isEmpty
            ? null
            : item.findElements(name).first;
        return node?.innerText.trim() ?? '';
      }

      final title = value('title');
      final link = value('link');
      var guid = value('guid');
      if (guid.isEmpty) guid = link;
      if (title.isEmpty || guid.isEmpty) continue;

      final categoryLabel = value('category');
      final key = categories[categoryLabel] ?? 'Life';
      final feedUrl = categoryFeedUrl(root, key);
      await _db.execute(
        'INSERT OR IGNORE INTO feeds (title, url, category, addedAt, origin) VALUES (?,?,?,?,?)',
        [
          sourceTitle + ' · ' + (categoryLabel.isEmpty ? '综合' : categoryLabel),
          feedUrl,
          key,
          now,
          'feedoverview',
        ],
      );
      final feedRows = await _db.select('SELECT id FROM feeds WHERE url = ?', [
        feedUrl,
      ]);
      if (feedRows.isEmpty) continue;
      final feedId = feedRows.first['id'] as int;

      var published = now;
      final rawDate = value('pubDate');
      if (rawDate.isNotEmpty) {
        try {
          published = HttpDate.parse(rawDate).millisecondsSinceEpoch;
        } catch (_) {
          try {
            published = DateTime.parse(rawDate).millisecondsSinceEpoch;
          } catch (_) {}
        }
      }

      await _db.execute(
        'INSERT OR REPLACE INTO feed_items (feedId, guid, title, link, preview, pubDate, fetchedAt, difficulty) VALUES (?,?,?,?,?,?,?,?)',
        [
          feedId,
          guid,
          title,
          link,
          value('description'),
          published,
          now,
          parseDifficulty(value('description')),
        ],
      );
      added++;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(lastSyncKey, DateTime.now().millisecondsSinceEpoch);
    return added;
  }

  /// 将 FeedOverview 的 description HTML 转为可复用的本地文章。
  Future<int> captureArticle(Map<String, dynamic> item) async {
    final guid = item['guid'] as String? ?? '';
    final link = item['link'] as String? ?? '';
    final title = item['title'] as String? ?? '未命名文章';
    final description = item['preview'] as String? ?? '';
    final blocks = parseDescription(description);
    if (blocks.isEmpty) throw StateError('FeedOverview 没有提供可读正文');
    final plain = blocks
        .where((block) => block['type'] == 'p')
        .map((block) => block['text'] as String)
        .join('\n\n');
    final wordCount = RegExp(r"[A-Za-z]+(?:['-][A-Za-z]+)*")
        .allMatches(plain)
        .length;
    final now = DateTime.now().millisecondsSinceEpoch;
    final difficulty =
        parseDifficulty(description) ?? (item['difficulty'] as int?);

    final existing = await _db.select(
      'SELECT id FROM articles WHERE guid = ?',
      [guid],
    );
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      await _db.execute(
        'UPDATE articles SET title=?, sourceUrl=?, html=?, plainText=?, blocks=?, wordCount=?, capturedAt=?, difficulty=? WHERE id=?',
        [
          title,
          link,
          description,
          plain,
          jsonEncode(blocks),
          wordCount,
          now,
          difficulty,
          id,
        ],
      );
      return id;
    }
    return _db.insertReturnId(
      'INSERT INTO articles (guid, title, sourceUrl, html, plainText, blocks, wordCount, capturedAt, difficulty) VALUES (?,?,?,?,?,?,?,?,?)',
      [
        guid,
        title,
        link,
        description,
        plain,
        jsonEncode(blocks),
        wordCount,
        now,
        difficulty,
      ],
    );
  }

  static List<Map<String, dynamic>> parseDescription(String description) {
    if (description.trim().isEmpty) return const [];
    final document = html_parser.parse(description);
    final blocks = <Map<String, dynamic>>[];
    for (final node in document.querySelectorAll('h2, h3, p, li, img')) {
      if (node.localName == 'img') {
        final src = (node.attributes['src'] ?? '').trim();
        if (!src.startsWith('http')) continue;
        final alt = (node.attributes['alt'] ?? '').trim();
        blocks.add({
          'type': 'img',
          'src': src,
          if (alt.isNotEmpty) 'alt': alt,
        });
        continue;
      }
      final text = node.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.length < 2) continue;
      if (text.contains('【AI 精简版】')) continue;
      if (_isFooterLine(text)) continue;
      blocks.add({'type': 'p', 'text': text});
    }
    if (!blocks.any((block) => block['type'] == 'p')) {
      final text =
          document.body?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
      if (text.length >= 20) blocks.add({'type': 'p', 'text': text});
    }
    return blocks;
  }

  /// The two trailing metadata paragraphs FeedOverview appends after the
  /// article: the source/published/difficulty line and the original link.
  /// They are ours to read, not the reader's to scroll past.
  static final _footerRe = RegExp(
    r'^(source|original link|原文链接)\s*:',
    caseSensitive: false,
  );

  static bool _isFooterLine(String text) => _footerRe.hasMatch(text);

  /// The 0–100 score FeedOverview writes into the metadata line, or null when
  /// the item carries none.
  static final _difficultyRe = RegExp(
    r'difficulty\s*:\s*(\d{1,3})\s*/\s*100',
    caseSensitive: false,
  );

  static int? parseDifficulty(String description) {
    final match = _difficultyRe.firstMatch(description);
    if (match == null) return null;
    final value = int.tryParse(match.group(1) ?? '');
    if (value == null) return null;
    return value.clamp(0, 100);
  }
}
