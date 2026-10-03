import 'package:xml/xml.dart';
import 'package:global_overview/services/http_service.dart';

class RssItem {
  final String guid;
  final String title;
  final String? link;
  final String? preview;
  final int? pubDate;
  RssItem({required this.guid, required this.title, this.link, this.preview, this.pubDate});
}

class RssService {
  final HttpService _http;
  RssService(this._http);

  Future<List<RssItem>> fetch(String url, {RetryPolicy retry = RetryPolicy.none}) async {
    final xmlText = await _http.getText(url, retry: retry);
    final doc = XmlDocument.parse(_safeXml(xmlText));
    final items = <RssItem>[];

    final rssItems = doc.findAllElements('item');
    if (rssItems.isNotEmpty) {
      for (final item in rssItems) {
        final title = _text(item.findElements('title')) ?? '';
        final link = _attrOrText(item.findElements('link'));
        final desc = _text(item.findElements('description')) ?? _text(item.findElements('encoded'));
        final guid = _text(item.findElements('guid')) ?? link ?? title;
        final pub = _date(item.findElements('pubDate'));
        if (title.isEmpty) continue;
        items.add(RssItem(guid: guid, title: _decode(title), link: link, preview: _strip(_decode(desc ?? '')), pubDate: pub));
      }
      return items;
    }

    final entries = doc.findAllElements('entry');
    for (final entry in entries) {
      final title = _text(entry.findElements('title')) ?? '';
      final links = entry.findElements('link').map((e) => e.getAttribute('href')).where((e) => e != null).cast<String>().toList();
      final link = links.isEmpty ? null : links.first;
      final summary = _text(entry.findElements('summary')) ?? _text(entry.findElements('content'));
      final guid = _text(entry.findElements('id')) ?? link ?? title;
      final pub = _date(entry.findElements('updated')) ?? _date(entry.findElements('published'));
      if (title.isEmpty) continue;
      items.add(RssItem(guid: guid, title: _decode(title), link: link, preview: _strip(_decode(summary ?? '')), pubDate: pub));
    }
    return items;
  }

  String _safeXml(String s) {
    final i = s.indexOf('<');
    return i > 0 ? s.substring(i) : s;
  }

  String? _text(Iterable<XmlNode> nodes) {
    if (nodes.isEmpty) return null;
    return nodes.first.innerText.trim();
  }

  String? _attrOrText(Iterable<XmlNode> nodes) {
    if (nodes.isEmpty) return null;
    final n = nodes.first;
    final href = n.getAttribute('href');
    if (href != null) return href;
    return n.innerText.trim().isEmpty ? null : n.innerText.trim();
  }

  int? _date(Iterable<XmlNode> nodes) {
    if (nodes.isEmpty) return null;
    final s = nodes.first.innerText.trim();
    if (s.isEmpty) return null;
    return _parseDate(s)?.millisecondsSinceEpoch;
  }

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// Atom 用 ISO-8601；RSS 用 RFC-822（`Mon, 02 Oct 2026 10:00:00 GMT`）。
  /// 注意：`DateTime.tryParse` **不认** RFC-822，必须自己解析，否则 pubDate 全为 null。
  DateTime? _parseDate(String input) {
    final iso = DateTime.tryParse(input);
    if (iso != null) return iso;
    final s = input.replaceAll(RegExp(r'\s+'), ' ').trim();
    final m = RegExp(r'^(?:[A-Za-z]{3},\s*)?(\d{1,2})\s+([A-Za-z]{3})\s+(\d{2,4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Za-z]{1,5})?\s*$')
        .firstMatch(s);
    if (m == null) return null;
    final month = _months[m.group(2)!.toLowerCase()];
    if (month == null) return null;
    var year = int.parse(m.group(3)!);
    if (year < 100) year += year < 70 ? 2000 : 1900;
    var offset = Duration.zero;
    final tz = m.group(7);
    if (tz != null && RegExp(r'^[+-]\d{4}$').hasMatch(tz)) {
      final sign = tz.startsWith('-') ? -1 : 1;
      offset = Duration(hours: sign * int.parse(tz.substring(1, 3)), minutes: sign * int.parse(tz.substring(3, 5)));
    }
    return DateTime.utc(
      year,
      month,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.tryParse(m.group(6) ?? '') ?? 0,
    ).subtract(offset);
  }

  String _decode(String s) {
    s = s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
    s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)));
    s = s.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)));
    s = s.replaceAll(RegExp(r'&[a-zA-Z]+;'), ' ');
    return s.trim();
  }

  String _strip(String? html) {
    if (html == null) return '';
    return html.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
