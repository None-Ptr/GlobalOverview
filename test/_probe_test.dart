import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Probe extends StatefulWidget {
  const Probe({super.key, required this.withOuterDetector});
  final bool withOuterDetector;
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
  int hits = 0;
  late final TapGestureRecognizer _tap;
  @override
  void initState() {
    super.initState();
    _tap = TapGestureRecognizer()..onTapDown = (_) => hits++;
  }
  @override
  void dispose() { _tap.dispose(); super.dispose(); }

  Widget _rich() => Text.rich(TextSpan(children: [
        const TextSpan(text: '\u2003\u2003'),
        TextSpan(text: 'alpha', recognizer: _tap),
        TextSpan(text: ' '),
        TextSpan(text: 'bravo', recognizer: _tap),
      ]));

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: widget.withOuterDetector
              ? GestureDetector(onLongPressStart: (_) {}, child: _rich())
              : _rich(),
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 回归点：外层包一层长按手势后，词内 TextSpan 的 recognizer 仍要能收到点击，
  // 否则点词查词会失灵。原来这里只 print 结果、不做断言，等于没有回归保护。
  testWidgets('无外层 GestureDetector 时词内点击可达', (tester) async {
    await tester.pumpWidget(const Probe(withOuterDetector: false));
    await tester.tap(find.byType(Text));
    await tester.pump();
    expect(tester.state<_ProbeState>(find.byType(Probe)).hits, 1);
  });

  testWidgets('有外层 GestureDetector(onLongPressStart) 不吞掉词内点击', (tester) async {
    await tester.pumpWidget(const Probe(withOuterDetector: true));
    await tester.tap(find.byType(Text));
    await tester.pump();
    expect(tester.state<_ProbeState>(find.byType(Probe)).hits, 1);
  });
}