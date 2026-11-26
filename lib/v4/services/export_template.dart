/// The template the export screen ships with. Markdown rather than HTML: the
/// output is meant to be pasted into notes, mailed, or read on a phone, and a
/// PDF already covers printing.
const String defaultQuestionTemplate = '''
# {{title}}
{{#if subtitle}}
{{subtitle}}
{{/if}}
{{count}} 题 · {{date}}

{{#each questions}}
{{index}}. {{prompt}}
{{#if options}}
{{options}}
{{/if}}
{{#if showAnswer}}
   答案：{{answer}}
{{/if}}
{{#if showAnalysis}}
   解析：{{analysis}}
{{/if}}
{{#if showMine}}
   我的作答：{{mine}}
{{/if}}
{{#if showQuote}}
   原文：{{sourceQuote}}
{{/if}}

{{/each}}''';

/// Variables a template may use, in the order the hint line lists them.
const String templateVariables =
    'title、subtitle、date、count；每题 prompt、options、answer、analysis、'
    'sourceQuote、mine；开关 showAnswer、showAnalysis、showMine、showQuote';

/// A mustache subset: `{{name}}`, `{{#each list}}…{{/each}}`, `{{#if flag}}…{{/if}}`.
///
/// Deliberately small. The template is a note format, not a page engine, and a
/// half-implemented handlebars would be worse than none: this one renders every
/// tag it documents and leaves anything else as written, so a typo shows up in
/// the preview instead of silently vanishing.
String renderExportTemplate(String source, Map<String, Object?> data) {
  final out = StringBuffer();
  _renderNodes(_parse(source), data, out);
  return out.toString();
}

/// Builds the scope a question template runs against.
Map<String, Object?> questionTemplateData({
  required String title,
  String subtitle = '',
  required List<Map<String, dynamic>> questions,
  required bool showAnswer,
  required bool showAnalysis,
  required bool showMine,
  required bool showQuote,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return {
    'title': title,
    'subtitle': subtitle,
    'count': questions.length,
    'date': '${at.year}-${two(at.month)}-${two(at.day)}',
    'questions': [
      for (final q in questions)
        {
          'prompt': '${q['prompt'] ?? ''}'.trim(),
          'options': _optionLines(q['options']),
          'answer': (q['answerList'] as List? ?? const []).join(' / '),
          'analysis': '${q['analysis'] ?? ''}'.trim(),
          'sourceQuote': '${q['sourceQuote'] ?? ''}'.trim(),
          'mine': '${q['final'] ?? ''}'.trim(),
          'showAnswer': showAnswer,
          'showAnalysis': showAnalysis,
          'showMine': showMine,
          'showQuote': showQuote,
        },
    ],
  };
}

/// Renders the question export as text. Used by the preview sheet and by the
/// Markdown download, so what the preview shows is exactly what gets written.
String renderQuestionExport(
  String template,
  Map<String, Object?> data,
) => '${renderExportTemplate(template, data).trimRight()}\n';

String _optionLines(Object? raw) {
  final list = raw is List ? raw : const [];
  final lines = <String>[];
  for (var i = 0; i < list.length; i++) {
    final label = String.fromCharCode(65 + i);
    final text = '${list[i]}'.trim();
    if (text.isNotEmpty) lines.add('   $label. $text');
  }
  return lines.join('\n');
}

// --- parser ---------------------------------------------------------------

sealed class _Node {
  const _Node();
}

class _TextNode extends _Node {
  final String text;
  const _TextNode(this.text);
}

class _VarNode extends _Node {
  final String key;
  const _VarNode(this.key);
}

class _BlockNode extends _Node {
  final String kind;
  final String key;
  final List<_Node> body = [];
  _BlockNode(this.kind, this.key);
}

List<_Node> _parse(String source) {
  final root = <_Node>[];
  final stack = <_BlockNode>[];
  void push(_Node node) =>
      stack.isEmpty ? root.add(node) : stack.last.body.add(node);

  var i = 0;
  while (i < source.length) {
    final open = source.indexOf('{{', i);
    if (open < 0) {
      push(_TextNode(source.substring(i)));
      break;
    }
    if (open > i) push(_TextNode(source.substring(i, open)));
    final close = source.indexOf('}}', open + 2);
    if (close < 0) {
      // An unclosed tag is text, not a crash.
      push(_TextNode(source.substring(open)));
      break;
    }
    final tag = source.substring(open + 2, close).trim();
    i = close + 2;
    if (tag.startsWith('#each ') || tag.startsWith('#if ')) {
      final kind = tag.startsWith('#each') ? 'each' : 'if';
      final block = _BlockNode(kind, tag.substring(kind.length + 2).trim());
      push(block);
      stack.add(block);
    } else if (tag.startsWith('/')) {
      if (stack.isNotEmpty) stack.removeLast();
    } else if (tag.isNotEmpty) {
      push(_VarNode(tag));
    }
  }
  return root;
}

void _renderNodes(
  List<_Node> nodes,
  Map<String, Object?> scope,
  StringBuffer out,
) {
  for (final node in nodes) {
    switch (node) {
      case _TextNode(:final text):
        out.write(text);
      case _VarNode(:final key):
        final value = scope[key];
        if (value == null) {
          out.write('{{$key}}');
        } else if (value is! Map && value is! List) {
          out.write('$value');
        }
      case _BlockNode(:final kind, :final key, :final body):
        final value = scope[key];
        if (kind == 'if') {
          if (_truthy(value)) _renderNodes(body, scope, out);
        } else if (value is List) {
          for (var i = 0; i < value.length; i++) {
            final item = value[i];
            final child = <String, Object?>{
              ...scope,
              'index': i + 1,
              if (item is Map) ...item.map((k, v) => MapEntry('$k', v)),
            };
            _renderNodes(body, child, out);
          }
        }
    }
  }
}

bool _truthy(Object? value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is String) return value.trim().isNotEmpty;
  if (value is num) return value != 0;
  if (value is List) return value.isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  return true;
}

/// True when the source parses and renders without leaving a stray block tag.
/// The export screen uses it to warn before saving something that will not run.
bool templateLooksValid(String source) {
  var depth = 0;
  for (final match in RegExp(r'\{\{\s*(/?)(#?)([^}]*)\}\}').allMatches(source)) {
    final closing = match.group(1) == '/';
    final opening = match.group(2) == '#';
    if (opening) {
      depth++;
    } else if (closing) {
      depth--;
      if (depth < 0) return false;
    }
  }
  return depth == 0;
}
