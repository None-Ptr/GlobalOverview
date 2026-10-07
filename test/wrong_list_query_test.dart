import 'package:flutter_test/flutter_test.dart';

import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/llm_service.dart';
import 'package:global_overview/services/quiz_service.dart';

import 'fake_db.dart';

class _RecDb extends FakeDb {
  final List<String> log = [];

  @override
  Future<List<Map<String, dynamic>>> select(String sql, [List<Object?>? params]) async {
    log.add(sql);
    if (sql.contains('JOIN answers')) {
      return [
        <String, dynamic>{
          'id': 2,
          'type': 'blank',
          'prompt': 'Q2',
          'options': '[]',
          'answers': '["b"]',
          'analysis': '解析',
          'sourceQuote': '',
          'final': 'w2',
          'comment': 'c2',
          'status': 'graded',
          'gradedAt': 150,
        }
      ];
    }
    return [];
  }
}

QuizService _svc(_RecDb db) => QuizService(LlmService(HttpService(), AppConfigService()), db);

void main() {
  test('loadWrongList 用受限 JOIN 查询，不再全表 SELECT *', () async {
    final db = _RecDb();
    final out = await _svc(db).loadWrongList();

    // 不得再出现无界全表拉取（questions / answers 只增不减）
    for (final q in db.log) {
      expect(q.contains('SELECT * FROM questions'), isFalse, reason: q);
      expect(q.contains('SELECT * FROM answers'), isFalse, reason: q);
    }
    // 应当是一条带 JOIN + GROUP BY 的受限查询
    expect(db.log.length, 1, reason: '应为单条查询: ${db.log}');
    expect(db.log.single, contains('JOIN answers'));
    expect(db.log.single, contains('GROUP BY questionId'));

    // 结果字段与解析正确（供错题本 / 错题导出共用）
    expect(out.length, 1);
    expect(out.first['answerList'], ['b']);
    expect(out.first['final'], 'w2');
    expect(out.first['comment'], 'c2');
  });
}
