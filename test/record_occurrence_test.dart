import 'package:flutter_test/flutter_test.dart';

import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/llm_service.dart';
import 'package:global_overview/services/vocab_service.dart';

import 'fake_db.dart';

/// 可控假库：记录 SQL 调用、按测试设定 insertReturnId / head 是否存在。
class _RecDb extends FakeDb {
  int insertId = 1;
  bool headExists = false;
  final List<String> calls = [];

  @override
  Future<int> insertReturnId(String sql, [List<Object?>? params]) async {
    calls.add('INSERT: $sql');
    return insertId;
  }

  @override
  Future<List<Map<String, dynamic>>> select(String sql, [List<Object?>? params]) async {
    calls.add('SELECT: $sql');
    if (sql.contains('FROM vocab_head')) {
      return headExists ? [<String, dynamic>{'head': 'test'}] : [];
    }
    return [];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {
    calls.add('EXEC: $sql');
  }
}

VocabService _svc(_RecDb db) => VocabService(db, LlmService(HttpService(), AppConfigService()));

void main() {
  const args = ('apple', 'An apple a day.', 'g1', 'Title', 'Src', 0, 3);

  test('recordOccurrence 重复位置（insertReturnId 返回 0）直接早退，不建/不更新 head', () async {
    final db = _RecDb()..insertId = 0;
    await _svc(db).recordOccurrence(args.$1, args.$2, args.$3, args.$4, args.$5, args.$6, args.$7);

    // 只应有写入 vocab_occ 的那一次 INSERT
    expect(db.calls.where((c) => c.startsWith('INSERT:')).length, 1,
        reason: '不应再发存在性 SELECT + 重复 INSERT');
    // 不得触碰 vocab_head（避免把 occCount 刷高）
    expect(db.calls.where((c) => c.contains('vocab_head')).isEmpty, isTrue);
    // 旧实现里那次存在性 SELECT 必须消失
    expect(db.calls.where((c) => c.contains('SELECT id FROM vocab_occ WHERE word')).isEmpty, isTrue);
  });

  test('recordOccurrence 新位置 + head 不存在：写入 vocab_occ 并新建 head', () async {
    final db = _RecDb()..insertId = 7..headExists = false;
    await _svc(db).recordOccurrence(args.$1, args.$2, args.$3, args.$4, args.$5, args.$6, args.$7);

    expect(db.calls.where((c) => c.startsWith('INSERT:')).length, 1);
    expect(db.calls.any((c) => c.contains('SELECT head FROM vocab_head')), isTrue);
    expect(db.calls.any((c) => c.contains('INSERT INTO vocab_head')), isTrue);
    expect(db.calls.any((c) => c.contains('UPDATE vocab_head')), isFalse);
  });

  test('recordOccurrence 新位置 + head 已存在：occCount +1 更新而非新建', () async {
    final db = _RecDb()..insertId = 9..headExists = true;
    await _svc(db).recordOccurrence(args.$1, args.$2, args.$3, args.$4, args.$5, args.$6, args.$7);

    expect(db.calls.any((c) => c.contains('INSERT INTO vocab_head')), isFalse);
    expect(db.calls.any((c) => c.contains('UPDATE vocab_head SET occCount')), isTrue);
  });
}
