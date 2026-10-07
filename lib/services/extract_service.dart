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

    // 原先对每个候选都querySelectorAll('p') 重算一遍，div 多的页面上是 O(候选数 × 段落数)。
    // 改成只遍历一次段落，把长度记到它各级祖先上；扣分项同理。
    // 语义与原来一致：得分 = Σ(长度≥25 的后代段落长度) - 20 × 后代 <a> 数。
    final scores = <Element, int>{};
    for (final p in doc.querySelectorAll('p')) {
      final len = p.text.trim().length;
      if (len < 25) continue;
      for (final anc in _selfAndAncestors(p)) {
        scores[anc] = (scores[anc] ?? 0) + len;
      }
    }
    for (final a in doc.querySelectorAll('a')) {
      for (final anc in _selfAndAncestors(a)) {
        scores[anc] = (scores[anc] ?? 0) - 20;
      }
    }

    Element? best;
    var bestScore = -1;
    for (final el in candidates) {
      final score = scores[el] ?? 0;
      if (score > bestScore) {
        bestScore = score;
        best = el;
      }
    }
    final root = best ?? doc.body ?? doc.documentElement!;

    final blocks = <ArticleBlock>[];
    final seenText = <String>{};
    for (final p in root.querySelectorAll('p,li,img,h2,h3')) {
      if (p.localName == 'img') {
        final src = _abs(p.attributes['src'], url);
        if (src != null && !_isBadImage(src)) {
          blocks.add(ArticleBlock(type: 'img', src: src, alt: p.attributes['alt']));
        }
      } else {
        final text = _clean(p.text);
        if (text.length < 25) continue;
        if (_isBoilerplate(text)) continue;
        // 源站常把导语段渲染两次（<h1> 旁的 dek + 正文首段），甚至两段都带 U+FEFF。
        // 这里按「归一化文本」去重：早期实现拿 Element 身份当 key，而 querySelectorAll
        // 本就不会重复返回同一元素，于是去重从未生效，重复段落会原样入库并污染出题。
        final key = _dedupKey(text);
        if (key.length >= _dedupMinLen && !seenText.add(key)) continue;
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

  /// 元素自身及其所有祖先（到 document 为止）。
  Iterable<Element> _selfAndAncestors(Element el) sync* {
    Element? cur = el;
    while (cur != null) {
      yield cur;
      cur = cur.parent;
    }
  }

  bool _isBoilerplate(String text) {
    final t = text.toLowerCase();
    return t.startsWith('cookie') || t.startsWith('subscribe') || t.startsWith('sign up') || t.startsWith('©') || t.startsWith('copyright');
  }

  /// 零宽字符 / BOM：源站正文里很常见（如 Verge 的导语段），肉眼不可见但会污染文本比对。
  static final _zeroWidth = RegExp('[\u200B\u200C\u200D\u2060\uFEFF]');

  /// 多余空白（连续空格、换行、缩进）。
  static final _spaces = RegExp(r'\s+');

  /// 短于此长度不做去重，避免误伤文章里刻意重复的短句。
  static const _dedupMinLen = 40;

  /// 清掉零宽字符并把空白归一。
  String _clean(String raw) => raw.replaceAll(_zeroWidth, '').replaceAll(_spaces, ' ').trim();

  /// 去重键：忽略大小写（空白已在 [_clean] 里归一）。
  String _dedupKey(String text) => text.toLowerCase();

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

  static final _reWord = RegExp(r'[A-Za-z]+');

  int _countWords(String text) => _reWord.allMatches(text).length;
}
