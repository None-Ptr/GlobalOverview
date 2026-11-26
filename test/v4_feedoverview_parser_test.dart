import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/services/feedoverview_service.dart';

void main() {
  test('解析 FeedOverview description 为正文段落', () {
    const html =
        '<p>【AI 精简版】</p><p>Climate policy is changing.</p><h2>Why it matters</h2><p>Local readers need context.</p>';
    final blocks = FeedOverviewService.parseDescription(html);
    expect(blocks.length, 3);
    expect(blocks.first['text'], 'Climate policy is changing.');
    expect(blocks[1]['text'], 'Why it matters');
  });

  test('空 description 不产生伪造正文', () {
    expect(FeedOverviewService.parseDescription(''), isEmpty);
    expect(FeedOverviewService.parseDescription('<div></div>'), isEmpty);
  });

  test('description 里的配图按原位置保留，相对地址丢弃', () {
    const html =
        '<p>Climate policy is changing fast.</p>'
        '<img src="https://cdn.example.com/chart.png" alt="Emissions chart">'
        '<img src="/relative.png">'
        '<p>Local readers need context.</p>';
    final blocks = FeedOverviewService.parseDescription(html);

    expect(blocks.length, 3);
    expect(blocks[1]['type'], 'img');
    expect(blocks[1]['src'], 'https://cdn.example.com/chart.png');
    expect(blocks[1]['alt'], 'Emissions chart');
  });

  test('末尾的来源/原文链接元数据段不进正文', () {
    const html =
        '<p>Climate policy is changing.</p>'
        '<p><strong>Source:</strong> Reuters | <strong>Published:</strong> 2026-11-24 21:43 UTC | '
        '<strong>Difficulty:</strong> 61/100</p>'
        '<p><strong>Original link:</strong> <a href="https://example.com/a">https://example.com/a</a></p>';
    final blocks = FeedOverviewService.parseDescription(html);

    expect(blocks.length, 1);
    expect(blocks.single['text'], 'Climate policy is changing.');
  });

  test('从元数据行读出 0–100 难度值', () {
    const html =
        '<p>Source: Reuters | Published: 2026-11-24 21:43 UTC | Difficulty: 61/100</p>';
    expect(FeedOverviewService.parseDifficulty(html), 61);
    expect(FeedOverviewService.parseDifficulty('<p>Difficulty: 7/100</p>'), 7);
  });

  test('没有难度值时返回 null，不伪造', () {
    expect(FeedOverviewService.parseDifficulty('<p>No metadata here.</p>'), isNull);
    expect(FeedOverviewService.parseDifficulty(''), isNull);
    expect(FeedOverviewService.parseDifficulty('Difficulty: abc/100'), isNull);
  });
}
