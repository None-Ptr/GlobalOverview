import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/services/share_service.dart';
import 'package:global_overview/v4/services/export_template.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ExportService {

  /// The built-in PDF fonts carry no CJK glyphs, so Chinese text used to print
  /// as nothing. A Noto Sans SC font is bundled as an asset and loaded once per
  /// session; it works offline, so the PDF never depends on fonts.gstatic.com
  /// being reachable at export time.
  pw.Font? _cjk;
  bool _cjkTried = false;

  Future<pw.Font?> _cjkFont() async {
    if (_cjkTried) return _cjk;
    _cjkTried = true;
    try {
      final data = await rootBundle.load('assets/fonts/NotoSansSC-VF.ttf');
      _cjk = pw.Font.ttf(data);
    } catch (_) {
      _cjk = null;
    }
    return _cjk;
  }

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
    final bytes = await buildQuestionsPdf(
      title: title,
      subtitle: subtitle,
      questions: questions,
      withAnswer: withAnswer,
      withAnalysis: withAnalysis,
      withMine: withMine,
      withQuote: withQuote,
      articleTitle: articleTitle,
      articleBody: articleBody,
      withArticle: withArticle,
    );
    try {
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (_) {
      // Some devices (emulators, ROMs without a print service) cannot open the
      // system print dialog. Fall back to handing the same PDF to the share
      // sheet so the export still completes instead of surfacing "操作失败".
      final outcome = await const ShareService().shareFile(
        bytes: bytes,
        fileName: '${safeFileName(title)}.pdf',
        mimeType: 'application/pdf',
        subject: title,
      );
      if (outcome == ShareOutcome.failed) {
        throw const AppException(
          'pdf_export_failed',
          '这台设备无法打开打印，也无法分享文件',
        );
      }
    }
  }

  /// The PDF as bytes: print, share and download all start here, so the file
  /// the reader sends is the same file they printed.
  Future<Uint8List> buildQuestionsPdf({
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
    final cjk = await _cjkFont();
    String label(String zh, String en) => cjk == null ? en : zh;
    final doc = pw.Document(
      theme: cjk == null ? null : pw.ThemeData.withFont(base: cjk, bold: cjk),
    );
    doc.addPage(
      pw.MultiPage(
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'GlobalOverview',
              style: const pw.TextStyle(fontSize: 8, color: pdf.PdfColors.grey600),
            ),
            pw.Text(
              '${ctx.pageNumber} / ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: pdf.PdfColors.grey600),
            ),
          ],
        ),
        build: (ctx) => [
          pw.Header(
            level: 0,
            text: title,
            textStyle: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          if (subtitle.isNotEmpty)
            pw.Text(
              subtitle,
              style: const pw.TextStyle(fontSize: 11, color: pdf.PdfColors.grey700),
            ),
          pw.SizedBox(height: 8),
          if (withArticle && articleBody.isNotEmpty) ...[
            if (articleTitle.isNotEmpty)
              pw.Header(level: 1, text: articleTitle),
            pw.Paragraph(
              text: articleBody,
              style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
            ),
            pw.SizedBox(height: 12),
          ],
          ...questions.asMap().entries.map((e) {
            final i = e.key;
            final q = e.value;
            final opts = q['options'] as List? ?? const [];
            final blocks = <pw.Widget>[
              pw.Paragraph(
                text: '${i + 1}. ${q['prompt'] ?? ''}',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
              if (opts.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 14, bottom: 4),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      for (var o = 0; o < opts.length; o++)
                        pw.Text(
                          '${String.fromCharCode(65 + o)}. ${opts[o]}',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                    ],
                  ),
                ),
              if (withAnswer)
                pw.Text(
                  '${label('参考答案', 'Answer')}: '
                  '${(q['answerList'] as List? ?? []).join(' / ')}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              if (withAnalysis && '${q['analysis'] ?? ''}'.isNotEmpty)
                pw.Text(
                  '${label('解析', 'Analysis')}: ${q['analysis']}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              if (withMine && '${q['final'] ?? ''}'.isNotEmpty)
                pw.Text(
                  '${label('我的作答', 'My answer')}: ${q['final']}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              if (withQuote && '${q['sourceQuote'] ?? ''}'.isNotEmpty)
                pw.Text(
                  '${label('原文', 'Quote')}: ${q['sourceQuote']}',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: pdf.PdfColors.grey800,
                  ),
                ),
              pw.SizedBox(height: 10),
            ];
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: blocks,
            );
          }),
        ],
      ),
    );
    return doc.save();
  }

  /// The template the reader edits, rendered to text. This is what the preview
  /// shows and what 分享 sends, so the template has one job and does it.
  String buildQuestionsText({
    required String template,
    required String title,
    String subtitle = '',
    required List<Map<String, dynamic>> questions,
    bool withAnswer = true,
    bool withAnalysis = true,
    bool withMine = false,
    bool withQuote = true,
  }) {
    final data = questionTemplateData(
      title: title,
      subtitle: subtitle,
      questions: questions,
      showAnswer: withAnswer,
      showAnalysis: withAnalysis,
      showMine: withMine,
      showQuote: withQuote,
    );
    return renderQuestionExport(template, data);
  }
}

/// A title that survives being a file name on every platform the app runs on.
String safeFileName(String title, {String fallback = 'export'}) {
  final cleaned = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return fallback;
  return cleaned.length <= 60 ? cleaned : cleaned.substring(0, 60).trim();
}
