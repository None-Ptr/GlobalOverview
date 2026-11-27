import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/screens/onboarding_screen.dart';
import 'package:global_overview/v4/services/onboarding_service.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('五步首启可完成并保存选择', (tester) async {
    V4Profile? completed;
    final service = OnboardingService();

    await tester.pumpWidget(
      MaterialApp(
        theme: V4Theme.light(),
        home: V4OnboardingScreen(
          service: service,
          onComplete: (profile) => completed = profile,
        ),
      ),
    );

    expect(find.textContaining('处在哪一步'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('v4-level-university')));
    await tester.tap(find.byKey(const ValueKey('v4-next')));
    await tester.pump();

    expect(find.textContaining('帮你完成什么'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('v4-goal-cet')));
    await tester.tap(find.byKey(const ValueKey('v4-next')));
    await tester.pump();

    expect(find.textContaining('哪些主题'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('v4-next')));
    await tester.pump();

    expect(find.textContaining('多少时间'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('v4-minutes-30')));
    await tester.tap(find.byKey(const ValueKey('v4-next')));
    await tester.pump();

    expect(find.text('这里能做什么'), findsOneWidget);
    expect(find.text('导入文章'), findsOneWidget);
    expect(find.text('AI 精选'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('v4-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(completed, isNotNull);
    expect(completed!.level, V4Level.university);
    expect(completed!.goal, V4Goal.cet);
    expect(completed!.minutes, 30);
    expect(completed!.completed, isTrue);
    expect((await service.load())?.completed, isTrue);
  });

  testWidgets('跳过使用默认值且不要求配置模型', (tester) async {
    V4Profile? completed;
    await tester.pumpWidget(
      MaterialApp(
        theme: V4Theme.light(),
        home: V4OnboardingScreen(
          service: OnboardingService(),
          onComplete: (profile) => completed = profile,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('v4-skip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(completed, isNotNull);
    expect(completed!.level, V4Level.highSchool);
    expect(completed!.minutes, 20);
  });
}
