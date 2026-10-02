import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/services/extract_service.dart';

/// 复现真实场景：The Verge 等站点会把导语段渲染两次（一次在 <h1> 旁的 header 块，
/// 一次在正文开头），两段文本还都带 U+FEFF 零宽字符。抽取后应只保留一条。
const _html = '''
<html><head><title>Headline</title></head><body>
<article>
  <div class="wrap">
    <div class="head">
      <h1>Apple's reportedly developing a smart home camera</h1>
      <p class="dek cbn62fh">\uFEFFWith Apple rumored to launch a smart home hub next month, it could come with a privacy-protecting camera.</p>
    </div>
    <div class="body">
      <p class="duet--article--dangerously-set-cms-markup">\uFEFFWith Apple rumored to launch a smart home hub next month, it could come with a privacy-protecting camera.</p>
      <p>Apple's rumored push into smart home tech could include a smart home security camera that never records video.</p>
      <p>They are also building home security products, both first-party and third-party home security cameras.</p>
    </div>
  </div>
</article>
</body></html>
''';

void main() {
  test('导语段在源站重复出现时只保留一条', () {
    final r = ExtractService().extract(_html);
    final texts = r.blocks.where((b) => b.type == 'p').map((b) => b.text ?? '').toList();

    expect(texts.where((t) => t.contains('With Apple rumored')).length, 1,
        reason: '导语段在 HTML 里出现两次，抽取后不应重复入库');
    expect(texts.length, 3, reason: '应剩 3 段正文');
  });

  test('正文不带零宽字符', () {
    final r = ExtractService().extract(_html);
    expect(r.plainText.contains('\uFEFF'), isFalse);
    expect(r.blocks.any((b) => (b.text ?? '').contains('\uFEFF')), isFalse);
  });

  test('同段落内的重复空白被归一（仍视为同一段）', () {
    const dup = '''
    <html><body><article><div>
      <p>With Apple rumored to launch a smart home hub next month, it could come with a privacy camera.</p>
      <p>With  Apple rumored to launch   a smart home hub next month, it could come with a privacy camera.</p>
      <p>Apple's rumored push into smart home tech could include a smart home security camera here.</p>
    </div></article></body></html>
    ''';
    final r = ExtractService().extract(dup);
    final texts = r.blocks.where((b) => b.type == 'p').map((b) => b.text ?? '').toList();
    expect(texts.length, 2, reason: '仅空白差异的同一段应被视作重复');
  });
}
