import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/v4/screens/migration_screen.dart';
import 'package:global_overview/v4/services/migration_service.dart';
import 'package:global_overview/v4/theme/v4_theme.dart';

class _FakeStore implements V4MigrationStore {
  bool migrated = false;

  @override
  Future<V4MigrationSummary> inspect() async => const V4MigrationSummary(
    vocabWords: 12,
    vocabOccurrences: 30,
    questionSets: 3,
    questions: 15,
    answers: 9,
    wrongAnswers: 4,
  );

  @override
  Future<bool> isComplete() async => migrated;

  @override
  Future<String?> migrate() async {
    migrated = true;
    return '/tmp/global_overview_v3_backup.db';
  }
}

void main() {
  testWidgets('迁移页展示真实数量并在确认后回调', (tester) async {
    final store = _FakeStore();
    String? backup;
    await tester.pumpWidget(
      MaterialApp(
        theme: V4Theme.light(),
        home: V4MigrationScreen(
          store: store,
          onComplete: (path) => backup = path,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('保留你的学习记录'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('v4-migrate')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(store.migrated, isTrue);
    expect(backup, '/tmp/global_overview_v3_backup.db');
  });
}
