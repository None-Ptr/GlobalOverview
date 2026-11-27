import 'dart:convert';

import 'package:global_overview/models/models.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/extract_service.dart';
import 'package:global_overview/services/feeds_service.dart';
import 'package:global_overview/services/http_service.dart';

/// Adds articles the reader wrote or linked themselves. They land in the same
/// feeds / feed_items / articles tables as fetched items, so the reading list,
/// reader, practice and word tools all work without a separate code path.
class ImportService {
  final DbService _db;
  final HttpService _http;

  ImportService(this._db, this._http);

  static const localFeedUrl = 'local://imported';
  static const localFeedTitle = '我的导入';
  static const localCategory = '我的导入';

  Future<int> importText({
    required String title,
    required String body,
  }) async {
    final name = title.trim();
    final text = body.trim();
    if (name.isEmpty) {
      throw const AppException('importTitle', '先给文章起个标题');
    }
    if (text.length < 20) {
      throw const AppException('importBody', '正文太短，至少写 20 个字');
    }
    final blocks = <ArticleBlock>[];
    for (final part in text.split(RegExp(r'\n\s*\n'))) {
      final paragraph = part.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
      if (paragraph.isNotEmpty) {
        blocks.add(ArticleBlock(type: 'p', text: paragraph));
      }
    }
    if (blocks.isEmpty) {
      throw const AppException('importBody', '没读到正文段落');
    }
    return _save(
      guid: 'manual-${DateTime.now().microsecondsSinceEpoch}',
      title: name,
      link: '',
      html: blocks
          .map((b) => '<p>${_escape(b.text ?? '')}</p>')
          .join('\n'),
      blocks: blocks,
      origin: 'imported',
    );
  }

  Future<int> importUrl({required String url}) async {
    final address = url.trim();
    final uri = Uri.tryParse(address);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const AppException('importUrl', '请输入以 http(s) 开头的文章网址');
    }
    final html = await _http.getText(address, retry: RetryPolicy.manual);
    final ex = ExtractService().extract(html, url: address);
    final text = ex.plainText.trim();
    if (text.isEmpty ||
        !ex.blocks.any((b) => b.type == 'p' && (b.text ?? '').trim().isNotEmpty)) {
      throw const AppException('emptyArticle', '没有抓到正文');
    }
    if (text.length < FeedsService.minPlainChars) {
      throw AppException(
        'tooShort',
        '正文过短（${text.length} 字），可能是付费墙或错误页',
      );
    }
    final lower = text.toLowerCase();
    for (final marker in FeedsService.blockedMarkers) {
      if (lower.contains(marker)) {
        throw const AppException('blocked', '抓到的是拦截页而不是正文');
      }
    }
    final title = (ex.title ?? '').trim().isEmpty ? uri.host : ex.title!.trim();
    return _save(
      guid: address,
      title: title,
      link: address,
      html: html,
      blocks: ex.blocks,
      origin: 'web',
    );
  }

  Future<int> _save({
    required String guid,
    required String title,
    required String link,
    required String html,
    required List<ArticleBlock> blocks,
    required String origin,
  }) async {
    final plain = blocks
        .where((b) => b.type == 'p')
        .map((b) => (b.text ?? '').trim())
        .where((text) => text.isNotEmpty)
        .join('\n\n');
    final wordCount = RegExp(r"[A-Za-z]+(?:['-][A-Za-z]+)*")
        .allMatches(plain)
        .length;
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.execute(
      'INSERT OR IGNORE INTO feeds (title, url, category, addedAt, origin) VALUES (?,?,?,?,?)',
      [localFeedTitle, localFeedUrl, localCategory, now, 'imported'],
    );
    final feeds = await _db.select('SELECT id FROM feeds WHERE url = ?', [
      localFeedUrl,
    ]);
    if (feeds.isEmpty) {
      throw const AppException('importFeed', '导入来源初始化失败');
    }
    final feedId = feeds.first['id'] as int;

    final exist = await _db.select('SELECT id FROM articles WHERE guid = ?', [
      guid,
    ]);
    final int articleId;
    if (exist.isNotEmpty) {
      articleId = exist.first['id'] as int;
      await _db.execute(
        'UPDATE articles SET title=?, sourceUrl=?, html=?, plainText=?, blocks=?, wordCount=?, capturedAt=?, origin=? WHERE id=?',
        [
          title,
          link,
          html,
          plain,
          jsonEncode(blocks.map((b) => b.toJson()).toList()),
          wordCount,
          now,
          origin,
          articleId,
        ],
      );
    } else {
      articleId = await _db.insertReturnId(
        'INSERT INTO articles (guid, title, sourceUrl, html, plainText, blocks, wordCount, capturedAt, origin) '
        'VALUES (?,?,?,?,?,?,?,?,?)',
        [
          guid,
          title,
          link,
          html,
          plain,
          jsonEncode(blocks.map((b) => b.toJson()).toList()),
          wordCount,
          now,
          origin,
        ],
      );
    }

    await _db.execute(
      'INSERT OR REPLACE INTO feed_items (feedId, guid, title, link, preview, pubDate, fetchedAt) '
      'VALUES (?,?,?,?,?,?,?)',
      [
        feedId,
        guid,
        title,
        link,
        plain.length > 200 ? plain.substring(0, 200) : plain,
        now,
        now,
      ],
    );
    return articleId;
  }

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
