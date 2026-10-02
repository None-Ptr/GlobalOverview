import 'dart:convert';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/llm_service.dart';

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
    final rows = await _db.select('SELECT * FROM questions WHERE setId = ? ORDER BY id ASC', [setId]);
    return _mapQuestions(rows);
  }

  Future<List<Map<String, dynamic>>> loadQuestionsByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    final ph = ids.map((_) => '?').join(',');
    final rows = await _db.select('SELECT * FROM questions WHERE id IN ($ph) ORDER BY id ASC', ids);
    return _mapQuestions(rows);
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

  static const examMap = {
    'cloze': {'label': '完形填空', 'prompt': 'Generate cloze (fill-in-the-blank) questions by removing key words.'},
    'choice': {'label': '阅读理解选择', 'prompt': 'Generate multiple-choice reading comprehension questions with 4 options.'},
    'blank': {'label': '语法填空', 'prompt': 'Generate grammar fill-in-the-blank questions.'},
    'match': {'label': '信息匹配', 'prompt': 'Generate matching questions.'},
    'tf': {'label': '判断正误', 'prompt': 'Generate true/false questions.'},
    'order': {'label': '句子排序', 'prompt': 'Generate sentence-ordering questions.'},
    'summary': {'label': '概要写作', 'prompt': 'Generate a summary-writing prompt.'},
    'translateEn': {'label': '英译中', 'prompt': 'Generate English-to-Chinese translation questions.'},
    'translateZh': {'label': '中译英', 'prompt': 'Generate Chinese-to-English translation questions.'},
    'vocab': {'label': '词汇运用', 'prompt': 'Generate vocabulary usage questions.'},
    'phrase': {'label': '短语填空', 'prompt': 'Generate phrase fill-in-the-blank questions.'},
    'rewrite': {'label': '句子改写', 'prompt': 'Generate sentence-rewriting questions.'},
    'open': {'label': '开放性问答', 'prompt': 'Generate open-ended questions.'},
  };

  Future<List<Map<String, dynamic>>> generate(String articleText, String type, int count) async {
    final info = examMap[type] ?? {'label': type, 'prompt': 'Generate questions.'};
    final prompt =
        'Based on the article, create $count ${info['label']} questions. ${info['prompt']}\nReturn a JSON array: [{"type":"$type","prompt":"","options":[] (only for choice/match/tf),"answers":[],"analysis":""}].';
    final res = await _llm.structured(
        'You are an English exam generator for Chinese high-school / IELTS learners.', '$prompt\n\nARTICLE:\n$articleText');
    if (res is List) return res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    if (res is Map && res['questions'] is List) {
      return (res['questions'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }
}
