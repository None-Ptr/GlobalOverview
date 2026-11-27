import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/v4/screens/quiz_screen.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ManualDb extends DbService {
  final List<List<Object?>> writes = [];

  @override
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?>? params,
  ]) async {
    if (sql.contains('gradeMode, prompt') && sql.contains('FROM questions')) {
      return [
        {
          'id': 1,
          'setId': 1,
          'type': 'choice',
          'gradeMode': 'manual',
          'prompt': 'Pick the right answer',
          'options': '["one","two"]',
          'answers': '["one"]',
          'analysis': '',
          'sourceQuote': 'the quoted source',
        },
      ];
    }
    if (sql.contains('FROM questions')) {
      return [
        {
          'id': 1,
          'answers': '["one"]',
          'gradeMode': 'manual',
        },
      ];
    }
    return [];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {
    writes.add(params ?? []);
  }

  @override
  Future<void> batch(
    List<({String sql, List<Object?> params})> statements,
  ) async {
    for (final statement in statements) {
      writes.add(statement.params);
    }
  }
}

Widget _app(DbService db) => ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: V4Theme.light(),
        home: const V4QuizScreen(setId: 1),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> submit(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.text('two'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('交卷'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('好'));
    await tester.pumpAndSettle();
    expect(find.text('待人工判分'), findsWidgets);
  }

  testWidgets('人工判分：判为正确后立刻显示结果并写库', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = _ManualDb();
    await tester.pumpWidget(_app(db));
    await submit(tester);

    expect(find.text('判为正确'), findsOneWidget);
    expect(find.text('判为错误'), findsOneWidget);

    await tester.tap(find.text('判为正确'));
    await tester.pumpAndSettle();

    expect(find.text('答对了'), findsOneWidget);
    expect(find.text('人工判为正确'), findsOneWidget);
    expect(find.text('判为正确'), findsNothing);
    expect(
      db.writes.any((p) => p.length == 6 && p[2] == 'graded' && p[0] == 1),
      isTrue,
    );
  });

  testWidgets('人工判分：判为错误后进入错题本状态', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = _ManualDb();
    await tester.pumpWidget(_app(db));
    await submit(tester);

    await tester.tap(find.text('判为错误'));
    await tester.pumpAndSettle();

    expect(find.text('答错了'), findsOneWidget);
    expect(find.text('人工判为错误'), findsOneWidget);
    expect(
      db.writes.any((p) => p.length == 6 && p[2] == 'graded' && p[1] == 1),
      isTrue,
    );
  });
}
