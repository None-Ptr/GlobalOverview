import 'dart:convert';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/llm_service.dart';
import 'package:global_overview/services/prompts.dart';

class QuizService {
  final LlmService _llm;
  final DbService _db;
  QuizService(this._llm, this._db);

  Future<List<Map<String, dynamic>>> _mapQuestions(List<Map<String, dynamic>> rows) async {
    return rows.map((r) {
      List<dynamic> opts = [];
      List<dynamic> ans = [];
      try {
        if (r['options'] != null) opts = jsonDecode(r['options'] as String);
      } catch (_) {}
      try {
        if (r['answers'] != null) ans = jsonDecode(r['answers'] as String);
      } catch (_) {}
      return {
        'id': r['id'],
        'setId': r['setId'],
        'type': r['type'],
        'gradeMode': r['gradeMode'],
        'prompt': r['prompt'],
        'options': opts,
        'answerList': ans,
        'analysis': r['analysis'],
        'sourceQuote': r['sourceQuote'],
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> loadSet(int setId) async {
    final rows = await _db.select(
        'SELECT id, setId, type, gradeMode, prompt, options, answers, analysis, sourceQuote FROM questions WHERE setId = ? ORDER BY id ASC',
        [setId]);
    return _mapQuestions(rows);
  }

  /// Rename a set's purpose label without touching its questions or answers.
  Future<void> setSetLabel(int setId, String label) async {
    await _db.execute(
      'UPDATE question_sets SET label = ? WHERE id = ?',
      [label, setId],
    );
  }

  /// 一篇文章历次生成的题集，按时间倒序。答案按「作答次数」统计而不是按题数：
  /// 同一道题可以重做多次，每一次都是真实发生过的事。
  Future<List<Map<String, dynamic>>> listSetsForArticle(int articleId) async {
    return _db.select(
      'SELECT s.id AS id, s.createdAt AS createdAt, s.label AS label, '
      'COUNT(DISTINCT q.id) AS questionCount, '
      'COUNT(a.id) AS attempts, '
      'SUM(CASE WHEN a.correct = 1 THEN 1 ELSE 0 END) AS correctAttempts '
      'FROM question_sets s '
      'LEFT JOIN questions q ON q.setId = s.id '
      'LEFT JOIN answers a ON a.questionId = q.id '
      'WHERE s.articleId = ? '
      'GROUP BY s.id '
      'ORDER BY s.createdAt DESC',
      [articleId],
    );
  }

  Future<List<Map<String, dynamic>>> loadQuestionsByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    // 分批查，规避 SQLite 绑定变量上限（「全部重做」大错题本会传入上千个 id）；
    // 分批后结果需重新按 id ASC 排序，保持与原 ORDER BY id ASC 一致。
    final rows = <Map<String, dynamic>>[];
    for (final chunk in chunked(ids)) {
      final ph = List.filled(chunk.length, '?').join(',');
      rows.addAll(await _db.select(
          'SELECT id, setId, type, gradeMode, prompt, options, answers, analysis, sourceQuote FROM questions WHERE id IN ($ph) ORDER BY id ASC',
          chunk));
    }
    rows.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
    return _mapQuestions(rows);
  }

  /// 错题本 / 错题导出共用：每题取最新一次作答，仅保留 `wrong = 1` 或 `status = 'pending'` 的题。
  ///
  /// 旧实现是 `SELECT * FROM questions` + `SELECT * FROM answers` 两张全表拉进内存再 join，
  /// 而 questions / answers 只增不减，重度用户会逼近 Android CursorWindow 上限，且 `SELECT *`
  /// 会把 `draft` / `options` / `sourceQuote` 等大字段一并拖进来。这里改成一条受限 JOIN，
  /// 结果行数由「错题数」决定，而不是「题目总数 + 作答总数」。
  Future<List<Map<String, dynamic>>> loadWrongList() async {
    final rows = await _db.select(
      'SELECT q.id AS id, q.type AS type, q.prompt AS prompt, q.options AS options, '
      'q.answers AS answers, q.analysis AS analysis, q.sourceQuote AS sourceQuote, '
      'a.final AS final, a.comment AS comment, a.status AS status, a.gradedAt AS gradedAt '
      'FROM questions q '
      'JOIN answers a ON a.questionId = q.id '
      'JOIN (SELECT questionId, MAX(gradedAt) AS g FROM answers GROUP BY questionId) m '
      '  ON m.questionId = a.questionId AND m.g = a.gradedAt '
      "WHERE a.wrong = 1 OR a.status = 'pending' "
      'ORDER BY q.id ASC',
    );
    return rows.map((r) {
      List<dynamic> opts = [];
      List<dynamic> ans = [];
      try {
        if (r['options'] != null) opts = jsonDecode(r['options'] as String);
      } catch (_) {}
      try {
        if (r['answers'] != null) ans = jsonDecode(r['answers'] as String);
      } catch (_) {}
      return <String, dynamic>{
        'id': r['id'],
        'type': r['type'],
        'prompt': r['prompt'],
        'options': opts,
        'answerList': ans,
        'analysis': r['analysis'],
        'sourceQuote': r['sourceQuote'],
        'final': r['final'],
        'comment': r['comment'],
        'status': r['status'] ?? 'graded',
        'gradedAt': r['gradedAt'],
      };
    }).toList();
  }

  /// 考试档位（对齐原 quiz.js 的 EXAM_MAP）：value 为出题约束描述，key 用作档位标识。
  static const examLevels = <String, String>{
    'PTJH': '小升初，禁止题目中出现未翻译的学术用语和高级词汇，主要考察信息检索能力。',
    'SHSEE': '中考，题目中仅可少量出现未翻译的高级词汇，不应出现未经翻译的学术用语，并考察较弱的推理能力。',
    'NCEE': '高考，需要考察综合应用能力，允许出现极少量（不超过2%）可通过构词法或上下文推导的学术词汇，严禁出现依赖专业背景的裸奔生僻词；重点考察复杂推理、高阶信息检索（区分事实与观点），以及对作者隐含态度和篇章结构的深层理解。',
    'CET4': '大学英语四级（词汇量约 4000），侧重同义替换与基本事实定位。',
    'CET6': '大学英语六级（词汇量约 5500），侧重长难句解构与抽象概念的具体化转述。',
    'TEM4': '英语专业四级（词汇量约 5500~6500），侧重语言学基础知识、文学常识、修辞手法和篇章结构的细粒度理解。',
    'TEM8': '英语专业八级（词汇量约 8000~10000，认知词汇量达 13000），考察文学修辞手法赏析、学术文本批判性思维及语言学逻辑。',
    'IELTS': '雅思（学术类，7+ 分目标），侧重扫读+精读效率切换，题型复杂（含判断/摘要），要求区分主次信息。',
    'TOEFL': '托福（100+ 分目标），侧重学科背景下的短期记忆负荷，重点考察总结题（排除次要细节）和指代关系。',
    'GRE': 'GRE（美国研究生入学），阅读文本词汇不偏怪，但逻辑极度复杂（多重嵌套、预设与反驳），重点考察基于文本证据的推理和作者态度微妙变化。',
    'GMAT': 'GMAT（管理学研究生），阅读部分侧重论证结构分析和批判性推理（如削弱/加强/假设识别），文本多涉及商业决策、生物科技等跨领域议题。',
    'SAT': 'SAT（美国本科入学），侧重历史文献类（建国文献/演说）的复古句式和循证阅读（必须找出上一题答案的原文证据），考察双篇对比关系。',
  };

  /// 题型显示名（对齐 quiz.js 的 typeLabel）。
  static String typeLabel(String? type) {
    final info = examMap[type];
    return info != null ? '${info['label']}' : (type ?? '题目');
  }

  /// 题型显示名（对齐 quiz.js 的 typeLabel）。出题规则在 `Prompts` 里，这里只管名字。
  static const examMap = {
    'cloze': {'label': '完形填空'},
    'choice': {'label': '阅读理解选择'},
    'blank': {'label': '语法填空'},
    'match': {'label': '信息匹配'},
    'tf': {'label': '判断正误'},
    'order': {'label': '句子排序'},
    'summary': {'label': '概要写作'},
    'translateEn': {'label': '英译中'},
    'translateZh': {'label': '中译英'},
    'vocab': {'label': '词汇运用'},
    'phrase': {'label': '短语填空'},
    'rewrite': {'label': '句子改写'},
    'open': {'label': '开放性问答'},
  };

  Future<List<Map<String, dynamic>>> generate(
    String articleText,
    String type,
    int count, {
    String? examLevel,
    String? instruction,
  }) {
    return _run(
      articleText,
      [type],
      [count],
      examLevel: examLevel,
      instruction: instruction,
    );
  }

  /// One call for a mixed set: [count] is the total, split as evenly as the
  /// numbers allow across [types].
  Future<List<Map<String, dynamic>>> generateMixed(
    String articleText,
    List<String> types,
    int count, {
    String? examLevel,
    String? instruction,
  }) {
    final picked = types.where(examMap.containsKey).toList();
    if (picked.isEmpty) return Future.value(const []);
    return _run(
      articleText,
      picked,
      _splitCount(count, picked.length),
      examLevel: examLevel,
      instruction: instruction,
    );
  }

  /// Single and mixed sets are the same prompt: the mix is a list of one.
  Future<List<Map<String, dynamic>>> _run(
    String articleText,
    List<String> types,
    List<int> counts, {
    String? examLevel,
    String? instruction,
  }) async {
    final plan = <PracticeItem>[
      for (var i = 0; i < types.length; i++)
        PracticeItem(
          type: types[i],
          label: typeLabel(types[i]),
          count: counts[i],
        ),
    ];
    final level = (examLevel != null && examLevel.isNotEmpty)
        ? (examLevels[examLevel] ?? examLevel)
        : null;
    final user = Prompts.practiceUser(
      plan: plan,
      article: LlmService.clipArticle(articleText),
      level: level,
      extra: instruction,
    );
    final res = await _llm.structured(
      Prompts.practiceSystem,
      user,
      operation: '生成练习',
    );
    return _parseQuestions(res);
  }

  /// Even split with the remainder going to the earlier types.
  static List<int> _splitCount(int count, int buckets) {
    final base = count ~/ buckets;
    final rest = count % buckets;
    return [for (var i = 0; i < buckets; i++) base + (i < rest ? 1 : 0)];
  }

  static List<Map<String, dynamic>> _parseQuestions(dynamic res) {
    if (res is List) {
      return res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (res is Map && res['questions'] is List) {
      return (res['questions'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }
}
