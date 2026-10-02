import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/rss_service.dart';

class _FakeHttp extends HttpService {
  final String body;
  _FakeHttp(this.body);
  @override
  Future<String> getText(String url, {Map<String, String>? headers}) async => body;
}

const _rss = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
<item>
  <title>A &amp; B &#8216;c&#8217;</title>
  <link>https://x/a</link>
  <description><![CDATA[<p>hello <b>world</b></p>]]></description>
  <pubDate>Fri, 02 Oct 2026 10:00:00 GMT</pubDate>
</item>
<item>
  <title>Second</title>
  <link>https://x/b</link>
  <pubDate>2026-10-01T08:30:00Z</pubDate>
</item>
</channel></rss>''';

void main() {
  test('RSS 的 RFC-822 pubDate 能被解析（DateTime.tryParse 认不了）', () async {
    final items = await RssService(_FakeHttp(_rss)).fetch('https://x');

    expect(items.length, 2);
    expect(items[0].pubDate, isNotNull, reason: 'RFC-822 格式不应解析成 null');
    expect(items[1].pubDate, isNotNull, reason: 'ISO-8601 也要支持');

    expect(DateTime.fromMillisecondsSinceEpoch(items[0].pubDate!, isUtc: true).toIso8601String(), '2026-10-02T10:00:00.000Z');
    expect(DateTime.fromMillisecondsSinceEpoch(items[1].pubDate!, isUtc: true).toIso8601String(), '2026-10-01T08:30:00.000Z');

    // 顺带覆盖实体解码与去标签
    expect(items[0].title, 'A & B ‘c’');
    expect(items[0].preview, 'hello world');
  });
}
