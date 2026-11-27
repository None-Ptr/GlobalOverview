import 'package:global_overview/v4/services/onboarding_service.dart';

String v4LevelLabel(V4Level level) {
  switch (level) {
    case V4Level.foundation:
      return '基础';
    case V4Level.highSchool:
      return '高中';
    case V4Level.university:
      return '大学';
    case V4Level.advanced:
      return '进阶';
  }
}

String v4GoalLabel(V4Goal goal) {
  switch (goal) {
    case V4Goal.school:
      return '课内提升';
    case V4Goal.cet:
      return '四六级';
    case V4Goal.postgraduate:
      return '考研';
    case V4Goal.ieltsToefl:
      return '雅思托福';
    case V4Goal.interest:
      return '兴趣阅读';
  }
}
