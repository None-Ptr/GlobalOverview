import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/v4/services/feedoverview_service.dart';

class _UrlDb extends DbService {
  _UrlDb(this.rows);

  final List<Map<String, dynamic>> rows;
  final updates = <List<Object?>>[];

  @override
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?>? params,
  ]) async {
    if (sql.contains('FROM feeds WHERE url LIKE')) return rows;
    if (sql.contains('FROM feeds WHERE url =')) {
      final url = params?.first;
      return rows.where((r) => r['url'] == url).map((r) => {'id': r['id']}).toList();
    }
    return [];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {
    if (sql.startsWith('UPDATE feeds SET url')) updates.add(params ?? const []);
  }
}

void main() {
  test('分类源地址按站点约定转小写', () {
    expect(
      FeedOverviewService.categoryFeedUrl('https://x.github.io/FO/', 'News'),
      'https://x.github.io/FO/feeds/news.xml',
    );
    expect(
      FeedOverviewService.categoryFeedUrl('https://x/', 'Books'),
      'https://x/feeds/books.xml',
    );
  });

  test('只改写文件名，不动自建根路径的大小写', () {
    expect(
      FeedOverviewService.canonicalFeedUrl('https://x/FeedOverview/feeds/News.xml'),
      'https://x/FeedOverview/feeds/news.xml',
    );
    expect(
      FeedOverviewService.canonicalFeedUrl('https://x/feeds/news.xml'),
      'https://x/feeds/news.xml',
    );
    expect(
      FeedOverviewService.canonicalFeedUrl('https://x/other/News.xml'),
      'https://x/other/News.xml',
    );
  });

  test('老库里的旧地址会被就地改成小写', () async {
    final db = _UrlDb([
      {'id': 1, 'url': 'https://x/feeds/News.xml'},
      {'id': 2, 'url': 'https://x/feeds/books.xml'},
    ]);

    await FeedOverviewService(db, HttpService()).repairFeedUrls('https://x/');

    expect(db.updates.length, 1);
    expect(db.updates.single[0], 'https://x/feeds/news.xml');
  });
}
