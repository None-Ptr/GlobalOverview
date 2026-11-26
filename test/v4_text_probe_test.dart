import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/services/text_probe.dart';

void main() {
  group('wordAt', () {
    const text = 'a single-number "word" is picked, right?';

    test('取到光标下的整词', () {
      final hit = wordAt(text, 4);
      expect(hit?.word, 'single-number');
      expect(text.substring(hit!.start, hit.end), 'single-number');
    });

    test('点在词后空白会吸附到前一个词', () {
      expect(wordAt('a single word here', 8)?.word, 'single');
    });

    test('连字符保留在词内，首尾连字符被裁掉', () {
      expect(wordAt(text, 3)?.word, 'single-number');
      expect(wordAt('--dash-- here', 3)?.word, 'dash');
    });

    test('纯标点与空白返回 null', () {
      expect(wordAt('...  ', 1), isNull);
      expect(wordAt('', 0), isNull);
    });

    test('越界偏移不会抛异常', () {
      expect(wordAt(text, 999)?.word, 'right');
      expect(wordAt(text, -5)?.word, 'a');
    });
  });

  group('sentenceAt', () {
    const text = 'First one. Second one! Third?';

    test('返回命中词所在的整句', () {
      expect(sentenceAt(text, 12, 18), 'Second one!');
    });

    test('跨句时回退到整段', () {
      expect(sentenceAt(text, 0, text.length), text);
    });
  });

  test('sentenceCount 数出句子数量', () {
    expect(sentenceCount('One. Two. Three.'), 3);
    expect(sentenceCount('   '), 0);
  });
}
