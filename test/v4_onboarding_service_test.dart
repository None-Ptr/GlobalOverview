import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/services/onboarding_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('首启未保存时返回未完成', () async {
    final service = OnboardingService();
    expect(await service.load(), isNull);
    expect(await service.isComplete(), isFalse);
  });

  test('保存后可完整恢复分层信息', () async {
    final service = OnboardingService();
    const profile = V4Profile(
      level: V4Level.university,
      goal: V4Goal.cet,
      interests: ['科学', '科技', '教育'],
      minutes: 30,
      completed: true,
    );

    await service.save(profile);
    final restored = await service.load();

    expect(restored, isNotNull);
    expect(restored!.level, V4Level.university);
    expect(restored.goal, V4Goal.cet);
    expect(restored.interests, ['科学', '科技', '教育']);
    expect(restored.minutes, 30);
    expect(restored.completed, isTrue);
    expect(await service.isComplete(), isTrue);
  });

  test('损坏的本地数据按未完成处理', () async {
    SharedPreferences.setMockInitialValues({
      OnboardingService.key: '{bad json',
    });
    final service = OnboardingService();
    expect(await service.load(), isNull);
    expect(await service.isComplete(), isFalse);
  });

  test('未知分层与目标回落默认值，缺失字段也补默认', () {
    final profile = V4Profile.fromJson({
      'level': 'unknown',
      'goal': 'unknown',
      'interests': ['科技', 42],
    });

    expect(profile.level, V4Level.highSchool);
    expect(profile.goal, V4Goal.school);
    expect(profile.interests, ['科技']);
    expect(profile.minutes, 20);
    expect(profile.completed, isFalse);

    final bare = V4Profile.fromJson(const {});
    expect(bare.interests, const ['科技', '科学', '文化', '生活', '教育']);
    expect(bare.minutes, 20);
  });

  test('字段类型不符时整份档案按未完成处理', () async {
    SharedPreferences.setMockInitialValues({
      OnboardingService.key: '{"minutes":"30"}',
    });
    expect(await OnboardingService().load(), isNull);
  });

  test('copyWith 只覆盖传入字段', () {
    const base = V4Profile(minutes: 15, completed: true);
    final next = base.copyWith(level: V4Level.advanced, interests: const ['设计']);

    expect(next.level, V4Level.advanced);
    expect(next.interests, const ['设计']);
    expect(next.minutes, 15);
    expect(next.completed, isTrue);
    expect(next.goal, base.goal);
  });
}
