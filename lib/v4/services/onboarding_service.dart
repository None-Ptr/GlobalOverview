import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum V4Level { foundation, highSchool, university, advanced }

enum V4Goal { school, cet, postgraduate, ieltsToefl, interest }

class V4Profile {
  final V4Level level;
  final V4Goal goal;
  final List<String> interests;
  final int minutes;
  final bool completed;

  const V4Profile({
    this.level = V4Level.highSchool,
    this.goal = V4Goal.school,
    this.interests = const ['科技', '科学', '文化', '生活', '教育'],
    this.minutes = 20,
    this.completed = false,
  });

  V4Profile copyWith({
    V4Level? level,
    V4Goal? goal,
    List<String>? interests,
    int? minutes,
    bool? completed,
  }) => V4Profile(
    level: level ?? this.level,
    goal: goal ?? this.goal,
    interests: interests ?? this.interests,
    minutes: minutes ?? this.minutes,
    completed: completed ?? this.completed,
  );

  Map<String, dynamic> toJson() => {
    'level': level.name,
    'goal': goal.name,
    'interests': interests,
    'minutes': minutes,
    'completed': completed,
  };

  factory V4Profile.fromJson(Map<String, dynamic> json) => V4Profile(
    level: V4Level.values.firstWhere(
      (e) => e.name == json['level'],
      orElse: () => V4Level.highSchool,
    ),
    goal: V4Goal.values.firstWhere(
      (e) => e.name == json['goal'],
      orElse: () => V4Goal.school,
    ),
    interests:
        (json['interests'] as List?)?.whereType<String>().toList() ??
        const ['科技', '科学', '文化', '生活', '教育'],
    minutes: (json['minutes'] as num?)?.toInt() ?? 20,
    completed: json['completed'] == true,
  );
}

class OnboardingService {
  static const key = 'v4_onboarding_profile';

  Future<V4Profile?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return V4Profile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(V4Profile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(profile.toJson()));
  }

  Future<bool> isComplete() async => (await load())?.completed == true;
}
