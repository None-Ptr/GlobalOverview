import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/v4/services/data_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers `PRAGMA table_info(...)` and records what the restore writes.
class _ImportDb extends DbService {
  final Map<String, List<String>> columns;
  final List<({String sql, List<Object?> params})> statements = [];

  _ImportDb({required this.columns});

  @override
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    List<Object?>? params,
  ]) async {
    final match = RegExp(r'PRAGMA table_info\((\w+)\)').firstMatch(sql);
    if (match != null) {
      final names = columns[match.group(1)] ?? const <String>[];
      return [
        for (final name in names) {'name': name},
      ];
    }
    return [];
  }

  @override
  Future<void> batch(
    List<({String sql, List<Object?> params})> batch,
  ) async {
    statements.addAll(batch);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const schema = {
    'vocab_head': ['head', 'kind', 'occCount', 'fsrs_state'],
    'answers': ['id', 'questionId', 'draft', 'final', 'correct', 'wrong'],
    'kv': ['key', 'value'],
  };

  String backup() => jsonEncode({
    'exportedAt': '2026-11-26T10:00:00.000',
    'profile': {'level': 'university', 'goal': 'ieltsToefl', 'minutes': 30},
    'vocabHead': [
      {'head': 'planet', 'kind': 'word', 'occCount': 3, 'unknownColumn': 1},
    ],
    'answers': [
      {'id': 7, 'questionId': 2, 'final': 'B', 'correct': 1, 'wrong': 0},
    ],
    'settings': [
      {'key': 'v4_daily_goal', 'value': '30'},
    ],
  });

  test('恢复备份先清表再按原 id 写回，未知列被丢掉', () async {
    final db = _ImportDb(columns: schema);
    final result = await V4DataService(db).importBackup(backup());

    expect(result.rows, 3);
    expect(result.tables, 3);
    expect(result.profile, isTrue);

    final sql = db.statements.map((s) => s.sql).toList();
    expect(sql, contains('DELETE FROM vocab_head'));
    expect(sql, contains('DELETE FROM answers'));
    expect(sql, contains('DELETE FROM kv'));

    final answerInsert = db.statements.firstWhere(
      (s) => s.sql.startsWith('INSERT OR REPLACE INTO answers'),
    );
    expect(answerInsert.sql, 'INSERT OR REPLACE INTO answers (id,questionId,final,correct,wrong) VALUES (?,?,?,?,?)');
    expect(answerInsert.params, [7, 2, 'B', 1, 0]);

    final vocabInsert = db.statements.firstWhere(
      (s) => s.sql.startsWith('INSERT OR REPLACE INTO vocab_head'),
    );
    expect(vocabInsert.sql, isNot(contains('unknownColumn')));
    expect(vocabInsert.params, ['planet', 'word', 3]);
  });

  test('恢复会带回学习档案', () async {
    await V4DataService(_ImportDb(columns: schema)).importBackup(backup());
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('v4_onboarding_profile');
    expect(raw, isNotNull);
    final profile = jsonDecode(raw!) as Map<String, dynamic>;
    expect(profile['level'], 'university');
    expect(profile['minutes'], 30);
  });

  test('不是备份的文件被拒绝，且不写任何语句', () async {
    final db = _ImportDb(columns: schema);
    await expectLater(
      V4DataService(db).importBackup('{"hello":1}'),
      throwsA(
        isA<AppException>().having((e) => e.code, 'code', 'backupEmpty'),
      ),
    );
    await expectLater(
      V4DataService(db).importBackup('not json'),
      throwsA(
        isA<AppException>().having((e) => e.code, 'code', 'backupInvalid'),
      ),
    );
    expect(db.statements, isEmpty);
  });

  test('导出的 JSON 能被自己读回来', () async {
    final source = _ImportDb(columns: schema);
    final json = await V4DataService(source).exportJson();
    final parsed = jsonDecode(json) as Map<String, dynamic>;
    expect(parsed.containsKey('exportedAt'), isTrue);
    expect(parsed.containsKey('vocabHead'), isTrue);
    expect(parsed.containsKey('settings'), isTrue);
  });
}
