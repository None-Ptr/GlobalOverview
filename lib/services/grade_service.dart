import 'dart:convert';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/llm_service.dart';
import 'package:global_overview/services/prompts.dart';
import 'package:global_overview/v4/services/ai_cost_service.dart';

class GradeService {
  final LlmService _llm;
  final DbService _db;
  GradeService(this._llm, this._db);

  /// 批量判分并写回 answers。items: [{questionId, final}]。
  /// 返回逐题结果与仍失败的题数。
  Future<({int pending, List<Map<String, dynamic>> results})> gradeBatch(List<Map<String, dynamic>> items) async {
    var pending = 0;
    final results = <Map<String, dynamic>>[];
    final updates = <({String sql, List<Object?> params})>[];

    // 一次取回全部题目，避免每题查一次库；按 id 分批，规避绑定变量上限（重判大错题本时 id 很多）。
    final ids = items.map((e) => e['questionId'] as int).toList();
    final qById = <int, Map<String, dynamic>>{};
    for (final chunk in chunked(ids)) {
      final ph = List.filled(chunk.length, '?').join(',');
      final rows = await _db.select(
        'SELECT id, answers, gradeMode, prompt FROM questions WHERE id IN ($ph)',
        chunk,
      );
      for (final r in rows) {
        qById[r['id'] as int] = r;
      }
    }

    // One confirmation for the whole batch: otherwise a five-question set
    // pops five cost sheets in a row.
    final aiInput = StringBuffer();
    var aiCount = 0;
    for (final item in items) {
      final qRow = qById[item['questionId'] as int];
      if (qRow == null) continue;
      final expected = (jsonDecode(qRow['answers'] as String? ?? '[]') as List)
          .map((e) => '$e')
          .toList();
      final answer = (item['final'] ?? '').toString().trim();
      final mode = (qRow['gradeMode'] as String? ?? 'ai').toLowerCase();
      if (mode != 'ai' || expected.isEmpty) continue;
      if (exactMatch(answer, expected)) continue;
      aiCount++;
      aiInput.writeln(
        Prompts.gradeUser(expected: expected.first, answer: answer),
      );
    }
    if (aiCount > 0) {
      await _llm.confirmCost(
        AiCostEstimator.estimateGrading(
          inputText: aiInput.toString(),
          count: aiCount,
          model: _llm.profile.model,
        ),
      );
    }

    for (final it in items) {
      final qid = it['questionId'] as int;
      final finalAns = (it['final'] ?? '') as String;
      try {
        final qRow = qById[qid];
        if (qRow == null) {
          pending++;
          results.add({'questionId': qid, 'correct': false, 'comment': '', 'status': 'pending'});
          continue;
        }
        final expected = (jsonDecode(qRow['answers'] as String? ?? '[]') as List).map((e) => '$e').toList();
        final a = finalAns.trim();
        final mode = (qRow['gradeMode'] as String? ?? 'ai').toLowerCase();
        final exact = exactMatch(a, expected);
        final Map<String, dynamic> res;
        switch (mode) {
          case 'manual':
            res = {
              'correct': false,
              'comment': '待人工判分',
              'status': 'pending',
            };
          case 'exact':
            res = {
              'correct': exact,
              'comment': exact ? '完全正确' : '与参考答案不一致',
            };
          case 'contains':
            final na = norm(a);
            final hit = na.isNotEmpty &&
                expected.any((e) {
                  final ne = norm(e);
                  return ne.isNotEmpty && na.contains(ne);
                });
            res = {
              'correct': hit,
              'comment': hit ? '包含参考答案' : '未包含参考答案',
            };
          default:
            // AI mode: an exact answer never needs a model call; every other
            // answer goes to the grader, and a failed call stays pending.
            res = exact
                ? {'correct': true, 'comment': '完全正确'}
                : (expected.isEmpty
                    ? {'correct': false, 'comment': ''}
                    : await grade(expected.first, finalAns, gate: false));
        }
        final pendingResult = res['status'] == 'pending';
        if (pendingResult) pending++;
        final correct = res['correct'] == true && !pendingResult ? 1 : 0;
        final status = pendingResult ? 'pending' : 'graded';
        // Collected and written in one transaction after the loop: the model
        // call dominates the wait, but twenty autocommits are still twenty
        // round trips.
        updates.add((
          sql:
              'UPDATE answers SET final = ?, correct = ?, wrong = ?, status = ?, comment = ?, gradedAt = ? WHERE questionId = ?',
          params: [
            finalAns,
            correct,
            correct == 1 ? 0 : 1,
            status,
            res['comment'],
            DateTime.now().millisecondsSinceEpoch,
            qid
          ],
        ));
        results.add({
          'questionId': qid,
          'correct': correct == 1,
          'comment': res['comment'],
          'status': status,
        });
      } catch (_) {
        pending++;
        results.add({'questionId': qid, 'correct': false, 'comment': '', 'status': 'pending'});
      }
    }
    await _db.batch(updates);
    return (pending: pending, results: results);
  }

  /// A human decision on a pending answer. Simple bookkeeping only: no model
  /// call, no XP, and the wrong book picks up the change from the DB.
  Future<void> gradeManually(int questionId, bool correct) async {
    await _db.execute(
      'UPDATE answers SET correct = ?, wrong = ?, status = ?, comment = ?, gradedAt = ? WHERE questionId = ?',
      [
        correct ? 1 : 0,
        correct ? 0 : 1,
        'graded',
        correct ? '人工判为正确' : '人工判为错误',
        DateTime.now().millisecondsSinceEpoch,
        questionId,
      ],
    );
  }

  /// Keeps letters and digits from every script, so a Chinese answer is not
  /// flattened into an empty string by the Latin-only filter.
  static final _reNonWord = RegExp(r'[^\p{L}\p{N} ]', unicode: true);
  static final _reSpaceRun = RegExp(r'\s+');

  static String norm(String s) => s
      .toLowerCase()
      .replaceAll(_reNonWord, '')
      .replaceAll(_reSpaceRun, ' ')
      .trim();

  /// Fast path shared by batch and single grading. An empty normalised string
  /// never matches: every string contains the empty string, which used to make
  /// any answer without ASCII letters "correct".
  static bool exactMatch(String answer, Iterable<String> expected) {
    final na = norm(answer).trim();
    if (na.isEmpty) return false;
    return expected.any((e) {
      final ne = norm(e).trim();
      return ne.isNotEmpty && na == ne;
    });
  }

  Future<Map<String, dynamic>> grade(
    String expected,
    String answer, {
    bool gate = true,
  }) async {
    final a = answer.trim();
    if (a.isEmpty) return {'correct': false, 'score': 0.0, 'comment': '未作答'};
    final e = expected.trim();
    if (exactMatch(a, [e])) {
      return {'correct': true, 'score': 1.0, 'comment': '完全正确'};
    }
    try {
      final res = await _llm.structured(
        Prompts.gradeSystem,
        Prompts.gradeUser(expected: expected, answer: answer),
        operation: '判分',
        gate: gate,
      );
      final map = res as Map<String, dynamic>;
      return {
        'correct': map['correct'] == true,
        'score': (map['score'] is num ? map['score'] : (map['correct'] == true ? 0.7 : 0.0)).toDouble(),
        'comment': map['comment']?.toString() ?? '',
      };
    } catch (_) {
      // A failed model call is not a wrong answer: leave it for a retry.
      return {
        'correct': false,
        'score': 0.0,
        'comment': '自动判分失败，可重试',
        'status': 'pending',
      };
    }
  }
}
