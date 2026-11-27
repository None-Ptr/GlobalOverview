import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/llm_service.dart';
import 'package:global_overview/services/vocab_service.dart';
import 'package:global_overview/v4/screens/vocab_screen.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';

import 'fake_db.dart';

class _FakeVocab extends VocabService {
  _FakeVocab({
    List<Map<String, dynamic>> heads = const [],
    this.due = 0,
    this.sentences = const [],
    this.occurrences = const {},
    this.failLoad = false,
  }) : heads = [...heads],
       super(FakeDb(), LlmService(HttpService(), AppConfigService()));

  final List<Map<String, dynamic>> heads;
  final int due;
  final List<Map<String, dynamic>> sentences;
  final Map<String, List<Map<String, dynamic>>> occurrences;
  final bool failLoad;
  Map<String, dynamic>? lastRemoved;
  int restoreCalls = 0;

  @override
  Future<void> syncHeadsFromCache() async {}

  @override
  Future<List<Map<String, dynamic>>> getHeads() async {
    if (failLoad) throw StateError('db broken');
    return heads;
  }

  @override
  Future<int> dueCount() async => due;

  @override
  Future<List<Map<String, dynamic>>> getSentences() async => sentences;

  @override
  Future<List<Map<String, dynamic>>> getOccurrence(String head) async =>
      occurrences[head] ?? const [];

  @override
  Future<Map<String, dynamic>> removeHeadSnapshot(String head) async {
    final index = heads.indexWhere((h) => h['head'] == head);
    final row = index >= 0 ? heads.removeAt(index) : null;
    lastRemoved = {'head': row, 'occ': occurrences[head] ?? const []};
    return lastRemoved!;
  }

  @override
  Future<void> restoreHead(Map<String, dynamic> snapshot) async {
    restoreCalls++;
    final row = snapshot['head'] as Map<String, dynamic>?;
    if (row != null) heads.insert(0, row);
  }
}

Map<String, dynamic> _word(
  String head, {
  String zh = '',
  String kind = 'word',
  int occCount = 1,
  int sourceCount = 1,
  int? dueInDays,
}) {
  return {
    'head': head,
    'kind': kind,
    'zh': zh,
    'occCount': occCount,
    'sourceCount': sourceCount,
    'latestSentence': 'A sentence about $head.',
    'fsrs_due': DateTime.now()
        .add(Duration(days: dueInDays ?? 3))
        .millisecondsSinceEpoch,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(VocabService vocab, {Widget? home}) => ProviderScope(
    overrides: [
      dbProvider.overrideWithValue(FakeDb()),
      vocabProvider.overrideWithValue(vocab),
    ],
    child: MaterialApp(
      theme: V4Theme.light(),
      home: home ?? const V4VocabScreen(),
    ),
  );

  testWidgets('没有生词时显示空态与引导', (tester) async {
    await tester.pumpWidget(host(_FakeVocab()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('还没有收藏的词汇'), findsOneWidget);
    expect(find.textContaining('在正文里点词'), findsOneWidget);
    expect(find.text('开始复习'), findsNothing);
  });

  testWidgets('生词行显示单词、释义、出现次数与下次复习时间', (tester) async {
    await tester.pumpWidget(
      host(
        _FakeVocab(
          heads: [
            _word('planet', zh: '行星', occCount: 3, sourceCount: 2, dueInDays: 2),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('planet'), findsOneWidget);
    expect(find.text('行星'), findsOneWidget);
    expect(find.textContaining('出现 3 次'), findsOneWidget);
    expect(find.textContaining('2 篇来源'), findsOneWidget);
    expect(find.textContaining('2 天后'), findsOneWidget);
  });

  testWidgets('有待复习时显示底部主按钮，待复习筛选只保留到期词', (tester) async {
    final past = _word('orbit', zh: '轨道', dueInDays: -1);
    final future = _word('planet', zh: '行星', dueInDays: 5);
    await tester.pumpWidget(host(_FakeVocab(heads: [past, future], due: 1)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('开始复习'), findsOneWidget);
    expect(find.text('planet'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('v4-vocab-filter-due')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('orbit'), findsOneWidget);
    expect(find.text('planet'), findsNothing);
  });

  testWidgets('点生词打开详情弹层并列出例句出处', (tester) async {
    await tester.pumpWidget(
      host(
        _FakeVocab(
          heads: [_word('planet', zh: '行星', occCount: 2, sourceCount: 1)],
          occurrences: {
            'planet': [
              {
                'articleGuid': 'g1',
                'articleTitle': '8 Tools To Measure Reading Levels',
                'sourceLabel': 'FeedOverview · 科学',
                'sentence': 'The planet is warming fast.',
                'paraIndex': 0,
                'tokIndex': 3,
                'at': DateTime.now().millisecondsSinceEpoch,
              },
            ],
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const ValueKey('v4-word-planet')));
    await tester.pumpAndSettle();

    expect(find.text('例句'), findsOneWidget);
    expect(find.textContaining('The planet is warming fast.'), findsOneWidget);
    expect(find.textContaining('FeedOverview · 科学'), findsOneWidget);
    expect(find.text('删除生词'), findsOneWidget);
  });

  testWidgets('删除生词后可以撤销，撤销后回到列表', (tester) async {
    final vocab = _FakeVocab(heads: [_word('planet', zh: '行星')]);
    await tester.pumpWidget(host(vocab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const ValueKey('v4-word-planet')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除生词'));
    await tester.pumpAndSettle();

    expect(find.text('planet'), findsNothing);
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(vocab.restoreCalls, 1);
    expect(find.text('planet'), findsOneWidget);
  });

  testWidgets('读取失败时显示错误态与重试', (tester) async {
    await tester.pumpWidget(host(_FakeVocab(failLoad: true)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('暂时无法读取词汇'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('句子页展示收藏句子与两个操作', (tester) async {
    await tester.pumpWidget(
      host(
        _FakeVocab(
          sentences: [
            {
              'sentence': 'The planet is warming fast.',
              'articleGuid': 'g1',
              'articleTitle': 'Tools To Measure Reading Levels',
              'sourceLabel': 'FeedOverview · 科学',
              'paraIndex': 0,
              'tokIndex': 3,
              'at': DateTime.now().millisecondsSinceEpoch,
            },
          ],
        ),
        home: const V4SentencesScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('The planet is warming fast.'), findsOneWidget);
    expect(find.text('回到原文'), findsOneWidget);
    expect(find.text('AI 拆解'), findsOneWidget);
  });
}
