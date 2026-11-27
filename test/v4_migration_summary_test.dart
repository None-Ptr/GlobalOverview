import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/services/migration_service.dart';

void main() {
  test('有生词、题集或作答时视为有学习数据', () {
    expect(const V4MigrationSummary().hasLearningData, isFalse);
    expect(const V4MigrationSummary(vocabWords: 1).hasLearningData, isTrue);
    expect(const V4MigrationSummary(questionSets: 1).hasLearningData, isTrue);
    expect(const V4MigrationSummary(answers: 1).hasLearningData, isTrue);
  });

  test('迁移摘要可序列化并完整恢复', () {
    const summary = V4MigrationSummary(
      vocabWords: 12,
      vocabOccurrences: 30,
      questionSets: 3,
      questions: 15,
      answers: 9,
      wrongAnswers: 4,
    );
    final restored = V4MigrationSummary.fromJson(summary.toJson());
    expect(restored.vocabWords, 12);
    expect(restored.vocabOccurrences, 30);
    expect(restored.questionSets, 3);
    expect(restored.questions, 15);
    expect(restored.answers, 9);
    expect(restored.wrongAnswers, 4);
  });
}
