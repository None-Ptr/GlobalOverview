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
    _tap = TapGestureRecognizer()..onTapDown = (_) { hits++; debugPrint('DBG onTapDown'); };
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

  testWidgets('无外层 GestureDetector', (tester) async {
    await tester.pumpWidget(const Probe(withOuterDetector: false));
    await tester.tap(find.byType(Text));
    await tester.pump();
    final s = tester.state<_ProbeState>(find.byType(Probe));
    print('RESULT no-outer hits=${s.hits}');
  });

  testWidgets('有外层 GestureDetector(onLongPressStart)', (tester) async {
    await tester.pumpWidget(const Probe(withOuterDetector: true));
    await tester.tap(find.byType(Text));
    await tester.pump();
    final s = tester.state<_ProbeState>(find.byType(Probe));
    print('RESULT with-outer hits=${s.hits}');
  });
}