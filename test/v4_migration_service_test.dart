import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/v4/services/migration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class _CountDb extends DbService {
  _CountDb({
    this.vocabWords = 0,
    this.vocabOccurrences = 0,
    this.questionSets = 0,
    this.questions = 0,
    this.answers = 0,
    this.wrongAnswers = 0,
  });

  final int vocabWords;
  final int vocabOccurrences;
  final int questionSets;
  final int questions;
  final int answers;
  final int wrongAnswers;
  final List<String> queries = [];

  static List<Map<String, dynamic>> _row(int value) => [
    {'c': value},
  ];

  @override
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?>? params,
  ]) async {
    queries.add(sql);
    if (sql.contains('FROM answers WHERE wrong')) return _row(wrongAnswers);
    if (sql.contains('FROM vocab_head')) return _row(vocabWords);
    if (sql.contains('FROM vocab_occ')) return _row(vocabOccurrences);
    if (sql.contains('FROM question_sets')) return _row(questionSets);
    if (sql.contains('FROM questions')) return _row(questions);
    if (sql.contains('FROM answers')) return _row(answers);
    return const [];
  }

  @override
  Future<Database> get database =>
      Future.error(StateError('database unavailable in test'));
}

class _EmptyDb extends DbService {
  @override
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?>? params,
  ]) async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('inspect 汇总各表计数，空表记为 0', () async {
    final db = _CountDb(
      vocabWords: 12,
      vocabOccurrences: 30,
      questionSets: 3,
      questions: 15,
      answers: 9,
      wrongAnswers: 4,
    );
    final summary = await V4MigrationService(db).inspect();

    expect(summary.vocabWords, 12);
    expect(summary.vocabOccurrences, 30);
    expect(summary.questionSets, 3);
    expect(summary.questions, 15);
    expect(summary.answers, 9);
    expect(summary.wrongAnswers, 4);
    expect(db.queries.length, 6);
  });

  test('inspect 在没有旧数据时全部返回 0', () async {
    final summary = await V4MigrationService(_EmptyDb()).inspect();
    expect(summary.vocabWords, 0);
    expect(summary.vocabOccurrences, 0);
    expect(summary.questionSets, 0);
    expect(summary.questions, 0);
    expect(summary.answers, 0);
    expect(summary.wrongAnswers, 0);
    expect(summary.hasLearningData, isFalse);
  });

  test('shouldPrompt 只在未迁移且有旧数据时为真', () async {
    final empty = V4MigrationService(_CountDb());
    expect(await empty.shouldPrompt(), isFalse);

    final withData = V4MigrationService(_CountDb(questionSets: 2));
    expect(await withData.shouldPrompt(), isTrue);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(V4MigrationService.completeKey, true);
    expect(await withData.shouldPrompt(), isFalse);
    expect(await withData.isComplete(), isTrue);
  });

  test('已迁移时 migrate 直接返回 null，不再访问数据库', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(V4MigrationService.completeKey, true);

    final db = _CountDb(vocabWords: 7);
    final result = await V4MigrationService(db).migrate();

    expect(result, isNull);
    expect(db.queries, isEmpty);
    expect(prefs.getString(V4MigrationService.summaryKey), isNull);
  });

  test('备份失败时不写入摘要也不标记完成', () async {
    final prefs = await SharedPreferences.getInstance();
    final service = V4MigrationService(_CountDb(vocabWords: 3));

    await expectLater(service.migrate(), throwsStateError);

    expect(prefs.getString(V4MigrationService.summaryKey), isNull);
    expect(prefs.getString(V4MigrationService.backupKey), isNull);
    expect(await service.isComplete(), isFalse);
    expect(await service.shouldPrompt(), isTrue);
  });
}
