/// RSS excerpts arrive as HTML fragments with numeric entities. Both wide
/// screens show them as sentences, never as markup.
String v4PlainText(String? html) {
  if (html == null || html.isEmpty) return '';
  final withoutTags = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
  final decoded = withoutTags.replaceAllMapped(
    RegExp(r'&#(x[0-9a-fA-F]+|\d+);'),
    (match) {
      final code = match.group(1)!;
      final value = code.startsWith('x')
          ? int.tryParse(code.substring(1), radix: 16)
          : int.tryParse(code);
      return value == null ? match.group(0)! : String.fromCharCode(value);
    },
  );
  return decoded
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// The line under a front-page headline. FeedOverview prefixes some excerpts
/// with its own editorial note; take the article's own "Why it is here" line
/// when it has one, otherwise the excerpt itself, and cut at a word boundary.
String v4Standfirst(String? html) {
  var text = v4PlainText(html);
  if (text.isEmpty) return '';
  const marker = 'Why it is here:';
  final at = text.indexOf(marker);
  if (at >= 0) {
    text = text.substring(at + marker.length).trimLeft();
  } else {
    text = text.replaceFirst(RegExp(r'^[【\[][^】\]]*[】\]]\s*'), '');
  }
  if (text.length > 220) {
    var cut = text.lastIndexOf(' ', 220);
    if (cut < 120) cut = 220;
    text = text.substring(0, cut).trimRight() + '…';
  }
  return text.trim();
}
