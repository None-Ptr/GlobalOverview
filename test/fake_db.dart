import 'package:global_overview/services/db_service.dart';

/// 测试用：不触碰 sqflite 的空实现。
class FakeDb extends DbService {
  @override
  Future<List<Map<String, dynamic>>> select(String sql, [List<Object?>? params]) async => [];
  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {}
  @override
  Future<void> clearCache() async {}
  @override
  Future<void> clearAll() async {}
  @override
  Future<void> deleteTables(List<String> tables) async {}
}

/// 带数据的假库：让精读单、题目、错题本、导出这些页真的排出卡片，
/// 而不只是空态。行结构与各页的查询列一一对应。
class RichFakeDb extends DbService {
  static const _question = {
    'id': 1,
    'setId': 1,
    'type': 'choice',
    'gradeMode': 'ai',
    'prompt':
        'According to the passage, what does the author imply about the long-term effect of reading?',
    'options': '["It fades quickly","It compounds over time","It matters little"]',
    'answers': '["It compounds over time"]',
    'analysis': 'The third paragraph contrasts short and long horizons.',
    'sourceQuote': 'the effect compounds',
  };

  @override
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?>? params,
  ]) async {
    if (sql.contains('FROM questions q')) {
      return [
        {
          'id': 1,
          'type': 'choice',
          'prompt': _question['prompt'],
          'options': _question['options'],
          'answers': _question['answers'],
          'analysis': _question['analysis'],
          'sourceQuote': _question['sourceQuote'],
          'final': 'It fades quickly',
          'comment': '选反了，再看第三段。',
          'status': 'graded',
          'gradedAt': 1700000000000,
        },
      ];
    }
    if (sql.contains('FROM questions')) return [_question];
    if (sql.contains('FROM question_sets')) {
      return [
        {'id': 1, 'articleId': 1, 'title': '阅读理解练习', 'qcount': 1},
      ];
    }
    if (sql.contains('FROM plan_items')) return [{'articleId': 1}];
    if (sql.contains('FROM presets')) {
      return [
        {'id': 1, 'name': '六级练习', 'config': '{"types":["choice"],"count":5}'},
      ];
    }
    if (sql.contains('FROM articles')) {
      return [
        {
          'id': 1,
          'guid': 'g-1',
          'title': 'Why long reading beats short scrolling',
          'wordCount': 1240,
          'hasCurated': 1,
          'plainText': 'body text',
          'curated_blocks': null,
        },
      ];
    }
    return [];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {}
  @override
  Future<void> clearCache() async {}
  @override
  Future<void> clearAll() async {}
  @override
  Future<void> deleteTables(List<String> tables) async {}
}
