import 'dart:convert';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/llm_service.dart';

class GradeService {
  final LlmService _llm;
  final DbService _db;
  GradeService(this._llm, this._db);

  /// 批量判分并写回 answers。items: [{questionId, final}]。
  /// 返回逐题结果与仍失败的题数。
  Future<({int pending, List<Map<String, dynamic>> results})> gradeBatch(List<Map<String, dynamic>> items) async {
    var pending = 0;
    final results = <Map<String, dynamic>>[];
    for (final it in items) {
      final qid = it['questionId'] as int;
      final finalAns = (it['final'] ?? '') as String;
      try {
        final qRows = await _db.select('SELECT answers, gradeMode FROM questions WHERE id = ?', [qid]);
        if (qRows.isEmpty) {
          pending++;
          results.add({'questionId': qid, 'correct': false, 'comment': '', 'status': 'pending'});
          continue;
        }
        final expected = (jsonDecode(qRows.first['answers'] as String? ?? '[]') as List).map((e) => '$e').toList();
        final a = finalAns.trim();
        bool? directCorrect;
        if (a.isNotEmpty) {
          final na = norm(a);
          for (final e in expected) {
            final ne = norm(e);
            if (na == ne || na.contains(ne) || ne.contains(na)) {
              directCorrect = true;
              break;
            }
          }
        }
        final res = directCorrect == true
            ? {'correct': true, 'comment': '完全正确'}
            : (expected.isEmpty ? {'correct': false, 'comment': ''} : await grade(expected.first, finalAns));
        final correct = res['correct'] == true ? 1 : 0;
        await _db.execute(
            'UPDATE answers SET final = ?, correct = ?, wrong = ?, status = ?, comment = ?, gradedAt = ? WHERE questionId = ?',
            [finalAns, correct, correct == 1 ? 0 : 1, 'graded', res['comment'], DateTime.now().millisecondsSinceEpoch, qid]);
        results.add({'questionId': qid, 'correct': correct == 1, 'comment': res['comment'], 'status': 'graded'});
      } catch (_) {
        pending++;
        results.add({'questionId': qid, 'correct': false, 'comment': '', 'status': 'pending'});
      }
    }
    return (pending: pending, results: results);
  }

  String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

  Future<Map<String, dynamic>> grade(String expected, String answer) async {
    final a = answer.trim();
    if (a.isEmpty) return {'correct': false, 'score': 0.0, 'comment': '未作答'};
    final e = expected.trim();
    if (norm(a) == norm(e)) return {'correct': true, 'score': 1.0, 'comment': '完全正确'};
    if (norm(a).contains(norm(e)) || norm(e).contains(norm(a))) {
      return {'correct': true, 'score': 0.9, 'comment': '基本正确'};
    }
    try {
      final res = await _llm.structured(
          'You are an English grader. Judge correctness (boolean) and give a 0-1 score plus a short Chinese comment. Return JSON {correct:bool,score:number,comment:string}.',
          'Expected: $expected\nAnswer: $answer');
      final map = res as Map<String, dynamic>;
      return {
        'correct': map['correct'] == true,
        'score': (map['score'] is num ? map['score'] : (map['correct'] == true ? 0.7 : 0.0)).toDouble(),
        'comment': map['comment']?.toString() ?? '',
      };
    } catch (_) {
      return {'correct': false, 'score': 0.0, 'comment': '自动判分失败'};
    }
  }
}
