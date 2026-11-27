import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/grade_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/llm_service.dart';
import 'package:global_overview/v4/services/ai_cost_service.dart';

class _FakeLlm extends LlmService {
  final Map<String, dynamic> result;
  final bool throws;
  int calls = 0;

  _FakeLlm(this.result, {this.throws = false})
      : super(HttpService(), AppConfigService());

  @override
  Future<dynamic> structured(
    String system,
    String user, {
    double temperature = 0.3,
    String operation = 'AI 操作',
    bool gate = true,
  }) async {
    calls++;
    if (throws) throw Exception('network down');
    return result;
  }
}

class _CountingLlm extends _FakeLlm {
  _CountingLlm() : super({'correct': false, 'score': 0.0, 'comment': 'x'});
  int gates = 0;

  @override
  Future<void> confirmCost(AiCostEstimate estimate) async {
    gates++;
  }
}

class _GradeDb extends DbService {
  final String? mode;
  final List<List<Object?>> writes = [];

  _GradeDb(this.mode);

  @override
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?>? params,
  ]) async {
    if (sql.contains('FROM questions')) {
      return [
        {
          'id': 1,
          'answers': '["Paris is the capital of France"]',
          'gradeMode': mode,
        },
      ];
    }
    return [];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {
    writes.add(params ?? []);
  }

  @override
  Future<void> batch(
    List<({String sql, List<Object?> params})> statements,
  ) async {
    for (final statement in statements) {
      writes.add(statement.params);
    }
  }
}

void main() {
  _FakeLlm fake() => _FakeLlm({
    'correct': false,
    'score': 0.0,
    'comment': 'AI 判定错误',
  });

  test('归一化保留中文，不再把中文答案抹成空串', () {
    expect(GradeService.norm('北京，中国！'), '北京中国');
    expect(GradeService.norm('Paris, France!'), 'paris france');
  });

  test('中文错答英文标准答案交给 AI 判错', () async {
    final llm = fake();
    final svc = GradeService(llm, DbService());
    final r = await svc.grade('Paris is the capital of France', '伦敦');

    expect(r['correct'], isFalse);
    expect(llm.calls, 1, reason: 'must reach the AI grader, not the fast path');
  });

  test('中文答案与中文标准答案不同也不算对', () async {
    final llm = fake();
    final svc = GradeService(llm, DbService());
    final r = await svc.grade('北京是中国的首都', '上海');

    expect(r['correct'], isFalse);
    expect(llm.calls, 1);
  });

  test('选项只是标准答案的子串时不再算对', () async {
    final llm = fake();
    final svc = GradeService(llm, DbService());
    final r = await svc.grade(
      'The company reported strong growth in Asia',
      'The company reported strong growth',
    );

    expect(r['correct'], isFalse);
    expect(llm.calls, 1);
  });

  test('归一化后完全相同仍然直接判对', () async {
    final llm = fake();
    final svc = GradeService(llm, DbService());
    final r = await svc.grade(
      'Paris is the capital of France',
      'paris is the capital of france!',
    );

    expect(r['correct'], isTrue);
    expect(r['comment'], '完全正确');
    expect(llm.calls, 0);
  });

  test('中文标点不影响完全一致', () async {
    final llm = fake();
    final svc = GradeService(llm, DbService());
    final r = await svc.grade('北京是中国的首都', '北京是中国的首都。');

    expect(r['correct'], isTrue);
    expect(llm.calls, 0);
  });

  test('空白答案不进入快速匹配', () {
    expect(GradeService.exactMatch('   ', ['anything']), isFalse);
    expect(GradeService.exactMatch(' anything ', ['anything!']), isTrue);
  });

  group('gradeMode 生效', () {
    Future<({int pending, List<Map<String, dynamic>> results})> batch(
      String? mode,
      String answer, {
      _FakeLlm? llm,
    }) {
      return GradeService(llm ?? fake(), _GradeDb(mode)).gradeBatch([
        {'questionId': 1, 'final': answer},
      ]);
    }

    test('精确：只认归一化完全一致，不调用模型', () async {
      final llm = fake();
      final res = await batch('exact', 'paris is the capital of france!', llm: llm);
      expect(res.results.single['correct'], isTrue);
      expect(res.results.single['status'], 'graded');
      expect(llm.calls, 0);

      final wrong = await batch('exact', '伦敦', llm: llm);
      expect(wrong.results.single['correct'], isFalse);
      expect(wrong.results.single['status'], 'graded');
      expect(llm.calls, 0);
    });

    test('包含：作答包含参考答案即为正确，空串不算包含', () async {
      final llm = fake();
      final hit = await batch(
        'contains',
        'In fact, Paris is the capital of France today.',
        llm: llm,
      );
      expect(hit.results.single['correct'], isTrue);
      expect(hit.results.single['status'], 'graded');
      expect(llm.calls, 0);

      final miss = await batch('contains', '伦敦', llm: llm);
      expect(miss.results.single['correct'], isFalse);
      expect(llm.calls, 0);
    });

    test('人工：直接挂待判，不调用模型', () async {
      final llm = fake();
      final db = _GradeDb('manual');
      final res = await GradeService(llm, db).gradeBatch([
        {'questionId': 1, 'final': 'anything'},
      ]);

      expect(res.pending, 1);
      expect(res.results.single['status'], 'pending');
      expect(res.results.single['comment'], '待人工判分');
      expect(llm.calls, 0);
      expect(db.writes.single[3], 'pending');
    });

    test('AI 模式模型失败时挂待判，不算答错', () async {
      final llm = _FakeLlm({}, throws: true);
      final db = _GradeDb('ai');
      final res = await GradeService(llm, db).gradeBatch([
        {'questionId': 1, 'final': '伦敦'},
      ]);

      expect(llm.calls, 1);
      expect(res.pending, 1);
      expect(res.results.single['status'], 'pending');
      expect(res.results.single['correct'], isFalse);
      expect(db.writes.single[3], 'pending');
    });

    test('一批多题只确认一次成本', () async {
      final llm = _CountingLlm();
      final db = _GradeDb('ai');
      final res = await GradeService(llm, db).gradeBatch([
        {'questionId': 1, 'final': '伦敦'},
        {'questionId': 1, 'final': '柏林'},
      ]);

      expect(res.results.length, 2);
      expect(llm.gates, 1);
      expect(llm.calls, 2);
    });

    test('模式缺省仍按 AI 判分', () async {
      final llm = fake();
      final res = await batch(null, '伦敦', llm: llm);
      expect(llm.calls, 1);
      expect(res.results.single['status'], 'graded');
      // The fake grader said false, so the result is a real graded miss.
      expect(res.results.single['correct'], isFalse);
    });
  });
}
