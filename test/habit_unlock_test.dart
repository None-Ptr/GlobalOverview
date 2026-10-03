import 'package:flutter_test/flutter_test.dart';

import 'package:global_overview/services/habit_service.dart';

import 'fake_db.dart';

class _MemDb extends FakeDb {
  final Map<String, String> kv = {};

  @override
  Future<List<Map<String, dynamic>>> select(String sql, [List<Object?>? params]) async {
    if (sql.contains('FROM kv') && params != null && params.isNotEmpty) {
      final v = kv[params.first];
      return v == null ? [] : [<String, dynamic>{'value': v}];
    }
    return [];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {
    if (sql.contains('INSERT OR REPLACE INTO kv') && params != null && params.length >= 2) {
      kv['${params[0]}'] = '${params[1]}';
    }
  }
}

void main() {
  test('首次满分交卷会返回新解锁的成就', () async {
    final svc = HabitService(_MemDb());
    final rec = await svc.recordCompletion(correct: 5, done: 5);
    expect(rec.newBadges.map((b) => b.id), contains('p1'));
    expect(rec.newBadges.map((b) => b.label), contains('初盈之喜'));
    expect(rec.newBadges.every((b) => b.unlocked && b.progress == 1.0), isTrue);
  });

  test('同一成就不会重复提示', () async {
    final svc = HabitService(_MemDb());
    final first = await svc.recordCompletion(correct: 5, done: 5);
    expect(first.newBadges, isNotEmpty);

    final second = await svc.recordCompletion(correct: 5, done: 5);
    expect(second.newBadges.map((b) => b.id), isNot(contains('p1')));
  });

  test('非满分交卷不解锁满分成就', () async {
    final svc = HabitService(_MemDb());
    final rec = await svc.recordCompletion(correct: 3, done: 5);
    expect(rec.newBadges.map((b) => b.id), isNot(contains('p1')));
  });
}