import 'dart:convert';

import 'package:global_overview/models/models.dart';
import 'package:global_overview/services/db_service.dart';

class V4Article {
  final int id;
  final String guid;
  final String title;
  final String sourceUrl;
  final List<ArticleBlock> blocks;
  final int wordCount;
  final bool isCondensed;

  /// FeedOverview's 0–100 score, null when the item carried none.
  final int? difficulty;

  /// The tightened version the reader generated, empty until it exists.
  final List<ArticleBlock> curated;

  const V4Article({
    required this.id,
    required this.guid,
    required this.title,
    required this.sourceUrl,
    required this.blocks,
    required this.wordCount,
    required this.isCondensed,
    this.difficulty,
    this.curated = const [],
  });

  bool get hasCurated => curated.isNotEmpty;

  /// Reading minutes at 200 words per minute, never below one.
  int get readingMinutes =>
      wordCount <= 0 ? 0 : (wordCount / 200).ceil().clamp(1, 999);

  bool get hasText =>
      blocks.any((block) => (block.text ?? '').trim().isNotEmpty);
}

class V4ArticleRepository {
  final DbService _db;
  V4ArticleRepository(this._db);

  /// 生词例句只带 guid，阅读器要数字 id。
  Future<int?> idByGuid(String guid) async {
    final rows = await _db.select('SELECT id FROM articles WHERE guid = ?', [
      guid,
    ]);
    return rows.isEmpty ? null : (rows.first['id'] as num?)?.toInt();
  }

  Future<V4Article> load(int id) async {
    final rows = await _db.select(
      'SELECT guid, title, sourceUrl, html, blocks, curated_blocks, wordCount, difficulty FROM articles WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) throw StateError('文章不存在');
    final row = rows.first;
    final html = row['html'] as String? ?? '';
    return V4Article(
      id: id,
      guid: row['guid'] as String? ?? '',
      title: row['title'] as String? ?? '未命名文章',
      sourceUrl: row['sourceUrl'] as String? ?? '',
      blocks: _decode(row['blocks'] as String?),
      wordCount: (row['wordCount'] as num?)?.toInt() ?? 0,
      isCondensed: html.contains('【AI 精简版】'),
      difficulty: (row['difficulty'] as num?)?.toInt(),
      curated: _decode(row['curated_blocks'] as String?),
    );
  }

  /// Stored blocks are JSON; anything unreadable is treated as absent rather
  /// than crashing the reader.
  static List<ArticleBlock> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      final blocks = <ArticleBlock>[];
      for (final item in list.whereType<Map>()) {
        final block = ArticleBlock.fromJson(Map<String, dynamic>.from(item));
        final text = block.text?.trim() ?? '';
        final src = block.src?.trim() ?? '';
        if (text.isNotEmpty || (block.type == 'img' && src.isNotEmpty)) {
          blocks.add(block);
        }
      }
      return blocks;
    } catch (_) {
      return const [];
    }
  }
}
