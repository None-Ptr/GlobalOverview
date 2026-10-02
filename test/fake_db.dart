import 'package:global_overview/services/db_service.dart';

/// 测试用：不触碰 sqflite 的空实现。
class FakeDb extends DbService {
  @override
  Future<List<Map<String, dynamic>>> select(String sql, [List<Object?>? params]) async => [];
  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {}
  @override
  Future<void> clearCache() async {}
  @override
  Future<void> clearAll() async {}
}
