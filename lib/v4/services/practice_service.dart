import 'dart:async';
import 'dart:convert';

import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/quiz_service.dart';

/// Turns an article into a stored practice set. The AI call goes through
/// [QuizService], which asks the cost gate for confirmation before sending.
class V4PracticeService {
  final DbService _db;
  final QuizService _quiz;

  V4PracticeService(this._db, this._quiz);

  Future<int> generate({
    required int articleId,
    required String title,
    List<String> types = const ['choice'],
    int count = 5,
    int? presetId,
    String? examLevel,
    String gradeMode = 'ai',
    String? instruction,
    String? label,
    void Function(int step, String detail)? onProgress,
  }) async {
    final picked = types.isEmpty ? const ['choice'] : types;
    final setLabel = (label == null || label.trim().isEmpty)
        ? (picked.length == 1
              ? QuizService.typeLabel(picked.first)
              : '混合练习')
        : label.trim();
    onProgress?.call(0, '正在读取正文');
    final text = await _articleText(articleId);
    if (text.trim().isEmpty) {
      throw const AppException('articleEmpty', '这篇文章的正文太短，先读原文再试');
    }
    final words = RegExp(r"[A-Za-z]+(?:['-][A-Za-z]+)*")
        .allMatches(text)
        .length;
    final stage = '已读取 $words 词，准备 ${picked.length} 种题型';
    onProgress?.call(1, stage);
    // A long generation can sit here for a minute; count the seconds so the
    // panel never looks frozen.
    var waited = 0;
    final ticker = onProgress == null
        ? null
        : Timer.periodic(const Duration(seconds: 1), (_) {
            waited++;
            onProgress(1, '$stage  已等待 ${waited}s');
          });
    final List<Map<String, dynamic>> questions;
    try {
      questions = await _quiz.generateMixed(
        text,
        picked,
        count,
        examLevel: examLevel,
        instruction: instruction,
      );
    } finally {
      ticker?.cancel();
    }
    if (questions.isEmpty) {
      throw const AppException('practiceEmpty', '这次没有生成出题目，请重试');
    }
    onProgress?.call(2, 'AI 生成了 ${questions.length} 道题，正在校验');
    final now = DateTime.now().millisecondsSinceEpoch;
    final setId = await _db.insertReturnId(
      'INSERT INTO question_sets (articleId, presetId, title, createdAt, label) VALUES (?,?,?,?,?)',
      [articleId, presetId, title, now, setLabel],
    );
    await _db.batch([
      for (final q in questions)
        (
          sql:
              'INSERT INTO questions (setId, type, gradeMode, prompt, options, answers, analysis, sourceQuote, createdAt) '
              'VALUES (?,?,?,?,?,?,?,?,?)',
          params: [
            setId,
            q['type'] ?? picked.first,
            q['gradeMode'] ?? gradeMode,
            q['prompt'] ?? '',
            jsonEncode(q['options'] ?? []),
            jsonEncode(q['answers'] ?? []),
            q['analysis'] ?? '',
            q['sourceQuote'] ?? '',
            now,
          ],
        ),
    ]);
    onProgress?.call(3, '已保存 ${questions.length} 道题');
    return setId;
  }

  /// Curated paragraphs first, raw extracted text second.
  Future<String> _articleText(int articleId) async {
    final rows = await _db.select(
      'SELECT plainText, curated_blocks FROM articles WHERE id = ?',
      [articleId],
    );
    if (rows.isEmpty) return '';
    final row = rows.first;
    final curated = <String>[];
    final raw = row['curated_blocks'] as String?;
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final block in (jsonDecode(raw) as List).whereType<Map>()) {
          if (block['type'] != 'p') continue;
          final text = '${block['text'] ?? ''}';
          if (text.isNotEmpty) curated.add(text);
        }
      } catch (_) {}
    }
    if (curated.isNotEmpty) return curated.join('\n\n');
    return row['plainText'] as String? ?? '';
  }
}
