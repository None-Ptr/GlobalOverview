import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ExportService {
  /// 导出题目为 PDF（对齐 export.vue 的开关项：参考答案/解析/我的作答/原文引用/原文）。
  Future<void> exportQuestions({
    required String title,
    String subtitle = '',
    required List<Map<String, dynamic>> questions,
    bool withAnswer = true,
    bool withAnalysis = true,
    bool withMine = false,
    bool withQuote = true,
    String articleTitle = '',
    String articleBody = '',
    bool withArticle = false,
  }) async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      build: (ctx) => [
        pw.Header(level: 0, text: title),
        if (subtitle.isNotEmpty) pw.Paragraph(text: subtitle),
        pw.SizedBox(height: 8),
        if (withArticle && articleBody.isNotEmpty) ...[
          if (articleTitle.isNotEmpty) pw.Header(level: 1, text: articleTitle),
          pw.Paragraph(text: articleBody),
          pw.SizedBox(height: 12),
        ],
        ...questions.asMap().entries.map((e) {
          final i = e.key;
          final q = e.value;
          final blocks = <pw.Widget>[
            pw.Paragraph(text: '${i + 1}. ${q['prompt'] ?? ''}'),
          ];
          final opts = q['options'] as List?;
          if (opts != null && opts.isNotEmpty) {
            blocks.add(pw.Paragraph(text: opts.map((o) => '  $o').join('\n')));
          }
          if (withAnswer) blocks.add(pw.Paragraph(text: '参考答案：${(q['answerList'] as List? ?? []).join(' / ')}'));
          if (withAnalysis && '${q['analysis'] ?? ''}'.isNotEmpty) blocks.add(pw.Paragraph(text: '解析：${q['analysis']}'));
          if (withMine && '${q['final'] ?? ''}'.isNotEmpty) blocks.add(pw.Paragraph(text: '我的作答：${q['final']}'));
          if (withQuote && '${q['sourceQuote'] ?? ''}'.isNotEmpty) blocks.add(pw.Paragraph(text: '原文：${q['sourceQuote']}'));
          blocks.add(pw.SizedBox(height: 10));
          return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: blocks);
        }),
      ],
    ));
    await Printing.layoutPdf(onLayout: (format) => doc.save());
  }
}
