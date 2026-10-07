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

    // 一次取回全部题目，避免每题查一次库；按 id 分批，规避绑定变量上限（重判大错题本时 id 很多）。
    final ids = items.map((e) => e['questionId'] as int).toList();
    final qById = <int, Map<String, dynamic>>{};
    for (final chunk in chunked(ids)) {
      final ph = List.filled(chunk.length, '?').join(',');
      final rows = await _db.select('SELECT id, answers, gradeMode FROM questions WHERE id IN ($ph)', chunk);
      for (final r in rows) {
        qById[r['id'] as int] = r;
      }
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

  static final _reNonAlnum = RegExp(r'[^a-z0-9 ]');
  static final _reSpaceRun = RegExp(r'\s+');

  String norm(String s) => s.toLowerCase().replaceAll(_reNonAlnum, '').replaceAll(_reSpaceRun, ' ').trim();

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
