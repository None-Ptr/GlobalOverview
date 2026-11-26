import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/llm_service.dart';
import 'package:global_overview/services/prompts.dart';
import 'package:global_overview/services/quiz_service.dart';

class _Capture extends LlmService {
  final dynamic response;
  String? system;
  String? user;
  _Capture(this.response) : super(HttpService(), AppConfigService());

  @override
  Future<dynamic> structured(
    String system,
    String user, {
    double temperature = 0.3,
    String operation = 'AI 操作',
    bool gate = true,
  }) async {
    this.system = system;
    this.user = user;
    return response;
  }
}

void main() {
  group('出题提示词', () {
    test('题型、数量、档位、补充要求都写进去，正文放在最后', () {
      final prompt = Prompts.practiceUser(
        plan: const [
          PracticeItem(type: 'choice', label: '阅读理解选择', count: 3),
          PracticeItem(type: 'tf', label: '判断正误', count: 2),
        ],
        article: 'ARTICLE BODY',
        level: '高考，考察综合应用能力',
        extra: '多考细节定位',
      );

      expect(prompt, contains('Exactly 5 items'));
      expect(prompt, contains('阅读理解选择'));
      expect(prompt, contains('3 question(s)'));
      expect(prompt, contains('判断正误'));
      expect(prompt, contains('2 question(s)'));
      expect(prompt, contains('Target level: 高考'));
      expect(prompt, contains('多考细节定位'));
      expect(prompt, contains('sourceQuote'));
      expect(prompt.trimRight().endsWith('ARTICLE BODY'), isTrue);
    });

    test('没有档位与补充要求时不留空段', () {
      final prompt = Prompts.practiceUser(
        plan: const [PracticeItem(type: 'choice', label: '阅读理解选择', count: 1)],
        article: 'body',
      );

      expect(prompt, isNot(contains('Target level')));
      expect(prompt, isNot(contains('EXTRA REQUIREMENTS')));
      expect(prompt, contains('upper-intermediate'));
    });

    test('多题型按总数均分，余数给前面的题型', () async {
      final llm = _Capture(<dynamic>[]);
      await QuizService(llm, DbService())
          .generateMixed('body', ['choice', 'tf', 'open'], 5);

      expect(llm.user, contains('2 question(s)'));
      expect(llm.user, contains('1 question(s)'));
      expect(llm.system, Prompts.practiceSystem);
    });

    test('单一题型走同一条提示词，不再有第二套模板', () async {
      final llm = _Capture(<dynamic>[]);
      await QuizService(llm, DbService()).generate('body', 'cloze', 4);

      expect(llm.user, contains('完形填空'));
      expect(llm.user, contains('Exactly 4 items'));
    });
  });

  group('其他提示词', () {
    test('判分把标准答案与作答分开列出', () {
      final prompt = Prompts.gradeUser(expected: 'in 1998', answer: '1998年');
      expect(prompt, contains('EXPECTED ANSWER\nin 1998'));
      expect(prompt, contains("LEARNER'S ANSWER\n1998年"));
      expect(prompt, contains('comment'));
    });

    test('词汇整理把生词 JSON 原样带上', () {
      final prompt = Prompts.organizeUser('[{"word":"tariff"}]');
      expect(prompt, contains('tariff'));
      expect(prompt, contains('"groups"'));
    });

    test('JSON 契约禁止代码块与多余文字', () {
      expect(Prompts.jsonOnly, contains('No Markdown fences'));
      expect(Prompts.jsonOnly, contains('first character must be { or ['));
    });
  });
}
