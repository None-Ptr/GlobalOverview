import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/services/export_template.dart';

void main() {
  test('替换变量，未知变量原样留下以便看见拼写错误', () {
    final out = renderExportTemplate(
      '{{title}} / {{count}} / {{nope}}',
      {'title': '阅读理解', 'count': 3},
    );
    expect(out, '阅读理解 / 3 / {{nope}}');
  });

  test('each 按顺序展开并给出从 1 开始的 index', () {
    final out = renderExportTemplate('{{#each items}}{{index}}.{{name}} {{/each}}', {
      'items': [
        {'name': 'a'},
        {'name': 'b'},
      ],
    });
    expect(out, '1.a 2.b ');
  });

  test('if 只在真值展开，空串与 false 都不展开', () {
    const source = '{{#if on}}Y{{/if}}{{#if off}}N{{/if}}{{#if blank}}B{{/if}}';
    expect(
      renderExportTemplate(source, {'on': true, 'off': false, 'blank': ''}),
      'Y',
    );
  });

  test('未闭合的块标签当作文字，不抛异常', () {
    expect(
      renderExportTemplate('{{#each items}}x', {'items': []}),
      '',
    );
    expect(renderExportTemplate('a {{b', {}), 'a {{b');
  });

  test('默认模板把一道题排成可读的条目', () {
    final text = renderQuestionExport(
      defaultQuestionTemplate,
      questionTemplateData(
        title: '阅读理解练习',
        questions: [
          {
            'prompt': 'What does the author imply?',
            'options': ['It fades', 'It compounds'],
            'answerList': ['It compounds'],
            'analysis': 'The third paragraph contrasts horizons.',
            'sourceQuote': 'the effect compounds',
            'final': 'It fades',
          },
        ],
        showAnswer: true,
        showAnalysis: true,
        showMine: false,
        showQuote: true,
        now: DateTime(2026, 11, 26),
      ),
    );

    expect(text, contains('# 阅读理解练习'));
    expect(text, contains('1 题 · 2026-11-26'));
    expect(text, contains('1. What does the author imply?'));
    expect(text, contains('   A. It fades'));
    expect(text, contains('   B. It compounds'));
    expect(text, contains('   答案：It compounds'));
    expect(text, contains('   解析：The third paragraph contrasts horizons.'));
    expect(text, contains('   原文：the effect compounds'));
    expect(text, isNot(contains('我的作答')));
  });

  test('关掉参考答案与原文引用后两项都不出现', () {
    final text = renderQuestionExport(
      defaultQuestionTemplate,
      questionTemplateData(
        title: 'T',
        questions: [
          {'prompt': 'Q', 'options': const [], 'answerList': ['A']},
        ],
        showAnswer: false,
        showAnalysis: false,
        showMine: false,
        showQuote: false,
      ),
    );
    expect(text, isNot(contains('答案：')));
    expect(text, isNot(contains('原文：')));
  });

  test('模板配对检查', () {
    expect(templateLooksValid(defaultQuestionTemplate), isTrue);
    expect(templateLooksValid('{{#if a}}x{{/if}}'), isTrue);
    expect(templateLooksValid('{{#if a}}x'), isFalse);
    expect(templateLooksValid('x{{/if}}'), isFalse);
    expect(templateLooksValid('{{title}}'), isTrue);
  });
}
