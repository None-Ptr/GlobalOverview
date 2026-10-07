import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/widgets/go_time_picker.dart';

void main() {
  testWidgets('预设可选、确定回传所选时间', (tester) async {
    TimeOfDay? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () async => captured = await showGoTimePicker(context: c, initialTime: const TimeOfDay(hour: 20, minute: 0)),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('提醒时间'), findsOneWidget);
    expect(find.text('每天 20:00 提醒你开始学习'), findsOneWidget);

    await tester.tap(find.text('睡前'));
    await tester.pumpAndSettle();
    expect(find.text('每天 22:30 提醒你开始学习'), findsOneWidget);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(captured, const TimeOfDay(hour: 22, minute: 30));
  });

  testWidgets('取消回传 null', (tester) async {
    TimeOfDay? captured;
    var done = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () async {
              captured = await showGoTimePicker(context: c, initialTime: const TimeOfDay(hour: 7, minute: 15));
              done = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('每天 07:15 提醒你开始学习'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(captured, isNull);
  });
}
