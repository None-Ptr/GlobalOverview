import 'package:html/parser.dart' as hp;
import 'package:html/dom.dart';
import 'package:global_overview/models/models.dart';

class ExtractResult {
  final String? title;
  final String? author;
  final List<ArticleBlock> blocks;
  final String plainText;
  final int wordCount;
  ExtractResult({this.title, this.author, required this.blocks, required this.plainText, required this.wordCount});
}

class ExtractService {
  ExtractResult extract(String html, {String? url}) {
    final doc = hp.parse(html);
    final title = _meta(doc, 'title') ?? doc.querySelector('h1')?.text.trim();
    final author = _meta(doc, 'author') ?? _meta(doc, 'article:author');

    doc.querySelectorAll('script,style,noscript,nav,footer,header,aside,form,iframe,svg').forEach((e) => e.remove());

    final candidates = <Element>[];
    for (final tag in ['article', 'main', 'section', 'div']) {
      candidates.addAll(doc.querySelectorAll(tag));
    }
    candidates.add(doc.body ?? doc.documentElement!);

    Element? best;
    var bestScore = -1;
    for (final el in candidates) {
      final score = _score(el);
      if (score > bestScore) {
        bestScore = score;
        best = el;
      }
    }
    final root = best ?? doc.body ?? doc.documentElement!;

    final blocks = <ArticleBlock>[];
    final seen = <Element>{};
    for (final p in root.querySelectorAll('p,li,img,h2,h3')) {
      if (seen.contains(p)) continue;
      seen.add(p);
      if (p.localName == 'img') {
        final src = _abs(p.attributes['src'], url);
        if (src != null && !_isBadImage(src)) {
          blocks.add(ArticleBlock(type: 'img', src: src, alt: p.attributes['alt']));
        }
      } else {
        final text = p.text.trim();
        if (text.length < 25) continue;
        if (_isBoilerplate(text)) continue;
        blocks.add(ArticleBlock(type: 'p', text: text));
      }
    }

    if (blocks.isEmpty) {
      final text = root.text.trim();
      if (text.isNotEmpty) blocks.add(ArticleBlock(type: 'p', text: text));
    }

    final plain = blocks.where((b) => b.type == 'p').map((b) => b.text ?? '').join('\n\n');
    final wordCount = _countWords(plain);
    return ExtractResult(title: title, author: author, blocks: blocks, plainText: plain, wordCount: wordCount);
  }

  int _score(Element el) {
    var score = 0;
    for (final p in el.querySelectorAll('p')) {
      final len = p.text.trim().length;
      if (len < 25) continue;
      score += len;
    }
    score -= el.querySelectorAll('a').length * 20;
    return score;
  }

  bool _isBoilerplate(String text) {
    final t = text.toLowerCase();
    return t.startsWith('cookie') || t.startsWith('subscribe') || t.startsWith('sign up') || t.startsWith('©') || t.startsWith('copyright');
  }

  bool _isBadImage(String src) {
    final s = src.toLowerCase();
    return s.contains('logo') || s.contains('icon') || s.contains('avatar') || s.contains('spinner') || s.endsWith('.gif');
  }

  String? _abs(String? src, String? base) {
    if (src == null || src.isEmpty) return null;
    if (src.startsWith('http')) return src;
    if (base == null) return null;
    try {
      return Uri.parse(base).resolve(src).toString();
    } catch (_) {
      return null;
    }
  }

  String? _meta(Document doc, String name) {
    final sel = doc.querySelector('meta[property="og:$name"],meta[name="$name"]');
    return sel?.attributes['content']?.trim();
  }

  int _countWords(String text) {
    final en = RegExp(r'[A-Za-z]+').allMatches(text).length;
    return en;
  }
}
