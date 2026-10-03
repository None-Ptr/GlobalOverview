import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/services/feeds_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/rss_service.dart';

import 'fake_db.dart';

class _Db extends FakeDb {
  final Map<String, Map<String, dynamic>> articles = {};
  int _next = 1;

  @override
  Future<List<Map<String, dynamic>>> select(String sql, [List<Object?>? params]) async {
    if (sql.contains('WHERE guid')) {
      final row = articles[params?[0] as String? ?? ''];
      return row == null ? [] : [row];
    }
    if (sql.contains('WHERE id')) {
      final hit = articles.values.where((e) => e['id'] == params?[0]).toList();
      if (hit.isEmpty) return [];
      return [
        {'wordCount': hit.first['wordCount'], 'plainText': hit.first['plainText']}
      ];
    }
    return [];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {
    if (sql.startsWith('INSERT INTO articles')) {
      final id = _next++;
      articles[params![0] as String] = {'id': id, 'wordCount': params[7], 'plainText': params[5]};
    } else if (sql.startsWith('UPDATE articles')) {
      final target = params![8];
      articles.forEach((k, v) {
        if (v['id'] == target) {
          v['plainText'] = params[4];
          v['wordCount'] = params[6];
        }
      });
    }
  }

  @override
  Future<int> insertReturnId(String sql, [List<Object?>? params]) async {
    final id = _next++;
    articles[params![0] as String] = {'id': id, 'wordCount': params[7], 'plainText': params[5]};
    return id;
  }
}

String _articleHtml({int paragraphs = 6}) {
  const filler = 'the quick brown fox jumps over the lazy dog and keeps running through the field. ';
  final body = StringBuffer('<html><head><title>Real Article</title></head><body><article>');
  for (var i = 0; i < paragraphs; i++) {
    body.write('<p>Paragraph $i: $filler$filler</p>');
  }
  body.write('</article></body></html>');
  return body.toString();
}

FeedsService _service(_Db db, http.Client client) {
  final net = HttpService(client: client);
  return FeedsService(db, RssService(net), net);
}

void main() {
  test('403 时不写库', () async {
    final db = _Db();
    final svc = _service(db, MockClient((req) async => http.Response('Forbidden', 403)));
    await expectLater(svc.captureArticle('g1', 'https://example.com/a', 'T'), throwsA(isA<AppException>().having((e) => e.code, 'code', 'http403')));
    expect(db.articles, isEmpty);
  });

  test('抓到拦截页时不写库', () async {
    final db = _Db();
    const note = 'Enable JavaScript and cookies to continue. Cloudflare Ray ID: 8f3a2b1c9d0e4f5a. Performance & security by Cloudflare. ';
    final svc = _service(db, MockClient((req) async => http.Response('<html><body><h1>Just a moment...</h1><p>$note$note$note</p></body></html>', 200)));
    await expectLater(svc.captureArticle('g1', 'https://example.com/a', 'T'), throwsA(isA<AppException>().having((e) => e.code, 'code', 'blocked')));
    expect(db.articles, isEmpty);
  });

  test('正文过短时不写库', () async {
    final db = _Db();
    final svc = _service(db, MockClient((req) async => http.Response('<html><body><p>too short</p></body></html>', 200)));
    await expectLater(svc.captureArticle('g1', 'https://example.com/a', 'T'), throwsA(isA<AppException>().having((e) => e.code, 'code', 'tooShort')));
    expect(db.articles, isEmpty);
  });

  test('正常文章入库，重复抓取命中缓存不重复请求', () async {
    final db = _Db();
    var calls = 0;
    final svc = _service(db, MockClient((req) async {
      calls++;
      return http.Response(_articleHtml(), 200);
    }));

    final first = await svc.captureArticle('g1', 'https://example.com/a', 'T');
    final second = await svc.captureArticle('g1', 'https://example.com/a', 'T');
    expect(first.id, second.id);
    expect(first.fresh, isTrue);
    expect(second.fresh, isFalse);
    expect(calls, 1);
  });

  test('force 重新抓取会覆盖旧行而不是新建', () async {
    final db = _Db();
    final svc = _service(db, MockClient((req) async => http.Response(_articleHtml(), 200)));
    final first = await svc.captureArticle('g1', 'https://example.com/a', 'T');
    final forced = await svc.captureArticle('g1', 'https://example.com/a', 'T', force: true);
    expect(forced.id, first.id);
    expect(forced.fresh, isTrue);
    expect(db.articles.length, 1);
  });

  test('looksUnusable 识别抓取守卫加入前的历史数据', () async {
    final db = _Db();
    final svc = _service(db, MockClient((req) async => http.Response(_articleHtml(), 200)));
    final ok = await svc.captureArticle('g1', 'https://example.com/a', 'T');
    expect(await svc.looksUnusable(ok.id), isFalse);

    db.articles['g1']!['plainText'] = 'too short';
    db.articles['g1']!['wordCount'] = 3;
    expect(await svc.looksUnusable(ok.id), isTrue);
  });
}
