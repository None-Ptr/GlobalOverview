import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:global_overview/models/models.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/screens/article_screen.dart';
import 'package:global_overview/theme/go_tokens.dart';

import 'fake_db.dart';

const _paras = 20;
const _wordsPerPara = 30;

String _paraText(int p) => [for (var i = 0; i < _wordsPerPara; i++) 'word${p}_$i'].join(' ');

class _ArtDb extends FakeDb {
  final List<String> log = [];

  @override
  Future<List<Map<String, dynamic>>> select(String sql, [List<Object?>? params]) async {
    log.add(sql);
    if (sql.contains('curated_blocks')) return [];
    // 正文现在是一次查询取齐 plainText/blocks。
    if (sql.contains('plainText, blocks')) {
      final blocks = [for (var p = 0; p < _paras; p++) ArticleBlock(type: 'p', text: _paraText(p))];
      return [
        {
          'id': 1,
          'title': 'T',
          'sourceUrl': 'https://x/',
          'wordCount': _paras * _wordsPerPara,
          'plainText': [for (var p = 0; p < _paras; p++) _paraText(p)].join('\n\n'),
          'blocks': jsonEncode(blocks.map((b) => b.toJson()).toList()),
        }
      ];
    }
    if (sql.contains('FROM articles')) {
      return [<String, dynamic>{'id': 1, 'title': 'T', 'sourceUrl': 'https://x/', 'wordCount': _paras * _wordsPerPara}];
    }
    return [];
  }
}

const _indent = '\u2003\u2003';

bool _hasHighlight(TextSpan span) {
  if (span.style?.backgroundColor != null) return true;
  final kids = span.children;
  if (kids == null) return false;
  for (final c in kids) {
    if (c is TextSpan && _hasHighlight(c)) return true;
  }
  return false;
}

/// 只有正文段带首行缩进，据此把段落从其它文本里区分出来。
List<RichText> _paragraphs(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .where((w) => w.text.toPlainText().startsWith(_indent))
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('打开文章只查一次正文，且不再读 html 大字段', (tester) async {
    // 与下面那条用例一样先给足视口：默认 800x600 放不下20 段正文会触发 overflow。
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = _ArtDb();

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: const MaterialApp(home: ArticleScreen(articleId: 1)),
    ));
    // 不用 pumpAndSettle：正文里的 Image.network 会挂起 HttpClient 超时定时器，
    // 且本页面渲染量大，settle 容易超时。这里只需要让首帧把正文查询跑完。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final body = db.log.where((s) => s.contains('FROM articles') && !s.contains('curated_blocks')).toList();
    expect(body.length, 1, reason: '正文应一次查齐，不该拆成多次: $body');
    expect(body.single, isNot(contains('html')), reason: 'html 是整页原文，阅读器从不读它: ${body.single}');

    // 卸载页面并把挂起的定时器跑干净，否则测试结束时会因 pending timer 失败。
    // TtsService.stop() 内部有 .timeout(4s)，必须 pump 满 5s 让该计时器走完。
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  group('选区 → 查询文本', () {
    test('整句保留词间空格', () {
      expect(ArticleScreen.cleanQueryText('Now is the time to act.'), 'Now is the time to act.');
      expect(ArticleScreen.cleanQueryText('  Now\u00A0is  the time  '), 'Now is the time');
      expect(ArticleScreen.cleanQueryText('word word'), 'word word');
    });

    test('单个词削掉周围标点', () {
      expect(ArticleScreen.cleanQueryText('word,'), 'word');
      expect(ArticleScreen.cleanQueryText('"quoted"'), 'quoted');
      expect(ArticleScreen.cleanQueryText("it's"), "it's");
      expect(ArticleScreen.cleanQueryText('e-mail,'), 'e-mail');
      expect(ArticleScreen.cleanQueryText('   '), '');
      expect(ArticleScreen.cleanQueryText('——'), '');
    });
  });

  testWidgets('点词命中：二分定位正确、只重建命中段', (tester) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(_ArtDb())],
      child: const MaterialApp(home: ArticleScreen(articleId: 1)),
    ));

    final sw = Stopwatch()..start();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    sw.stop();
    // ignore: avoid_print
    print('RESULT build ${_paras * _wordsPerPara} words = ${sw.elapsedMilliseconds}ms');

    expect(_paragraphs(tester).length, _paras);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(tester.widget<Icon>(find.byIcon(Icons.menu)).color, Go.primary, reason: '选词模式应已开启');

    final first = _paragraphs(tester).first;

    // Text.rich 会把传入的 span 再包一层，取真正的内容 span
    final root = (first.text as TextSpan).children!.first as TextSpan;
    final ranges = <({int start, int end})>[];
    var off = 0;
    for (final s in root.children!) {
      final len = s.toPlainText().length;
      if (s is TextSpan && s.recognizer != null) ranges.add((start: off, end: off + len));
      off += len;
    }
    expect(ranges, isNotEmpty, reason: '词 span 应挂上点击识别器');

    final rp = tester.renderObject<RenderParagraph>(find.byWidget(first));
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: ranges.first.start, extentOffset: ranges.first.end));
    expect(boxes, isNotEmpty);
    // getBoxesForSelection 返回的是段落局部坐标，必须转成全局坐标才能点
    final wordCenter = rp.localToGlobal(boxes.first.toRect().center);

    final sw2 = Stopwatch()..start();
    await tester.tapAt(wordCenter);
    await tester.pump();
    sw2.stop();
    // ignore: avoid_print
    print('RESULT tap frame = ${sw2.elapsedMilliseconds}ms');

    expect(tester.takeException(), isNull);

    final lit = _paragraphs(tester).where((w) => _hasHighlight(w.text as TextSpan)).length;
    expect(lit, 1, reason: '点击应命中某个词，且只有该段被重建');

    // 长按落在空白/标点上：应回退为选中整段
    final space = rp.getBoxesForSelection(TextSelection(baseOffset: ranges.first.end, extentOffset: ranges.first.end + 1));
    expect(space, isNotEmpty);
    await tester.longPressAt(rp.localToGlobal(space.first.toRect().center));
    await tester.pump();
    expect(find.textContaining('word0_0'), findsWidgets, reason: '长按空白应选中整段并出现选区条');

    // 显式卸载以在测试内触发 dispose，并让 TtsService.stop() 的 timeout 计时器走完
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}