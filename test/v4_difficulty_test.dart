import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:global_overview/v4/widgets/v4_difficulty.dart';

Widget _host(Widget child) => MaterialApp(
      theme: V4Theme.light(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  test('难度分档覆盖 0–100 的边界', () {
    expect(V4Difficulty.tierOf(0), V4DifficultyTier.foundation);
    expect(V4Difficulty.tierOf(51), V4DifficultyTier.foundation);
    expect(V4Difficulty.tierOf(52), V4DifficultyTier.school);
    expect(V4Difficulty.tierOf(62), V4DifficultyTier.school);
    expect(V4Difficulty.tierOf(63), V4DifficultyTier.college);
    expect(V4Difficulty.tierOf(74), V4DifficultyTier.college);
    expect(V4Difficulty.tierOf(75), V4DifficultyTier.advanced);
    expect(V4Difficulty.tierOf(100), V4DifficultyTier.advanced);
    expect(V4Difficulty.tierOf(null), isNull);
  });

  test('每个档位都预选一个考试档位', () {
    expect(V4DifficultyTier.foundation.level, 'SHSEE');
    expect(V4DifficultyTier.school.level, 'NCEE');
    expect(V4DifficultyTier.college.level, 'CET6');
    expect(V4DifficultyTier.advanced.level, 'IELTS');
  });

  testWidgets('有分数显示档位词，无分数什么都不显示', (tester) async {
    await tester.pumpWidget(_host(const V4Difficulty(score: 66)));
    expect(find.text('大学'), findsOneWidget);

    await tester.pumpWidget(_host(const V4Difficulty(score: null)));
    expect(find.byType(V4Difficulty), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(V4Difficulty),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
  });

  testWidgets('列表里的紧凑形态只显示档位词', (tester) async {
    await tester.pumpWidget(
      _host(const V4Difficulty(score: 45, showScale: false)),
    );
    expect(find.text('基础'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(V4Difficulty),
        matching: find.byType(Container),
      ),
      findsNothing,
    );
  });
}
