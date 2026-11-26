import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/services/onboarding_service.dart';
import 'package:global_overview/v4/services/profile_labels.dart';

void main() {
  test('每个水平与目标都有中文标签', () {
    expect(
      V4Level.values.map(v4LevelLabel).toList(),
      ['基础', '高中', '大学', '进阶'],
    );
    expect(
      V4Goal.values.map(v4GoalLabel).toList(),
      ['课内提升', '四六级', '考研', '雅思托福', '兴趣阅读'],
    );
  });

  test('标签没有空串或重复', () {
    final labels = [
      ...V4Level.values.map(v4LevelLabel),
      ...V4Goal.values.map(v4GoalLabel),
    ];
    expect(labels.any((l) => l.trim().isEmpty), isFalse);
    expect(labels.toSet().length, labels.length);
  });
}
