import 'package:flutter_test/flutter_test.dart';

import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/llm_service.dart';
import 'package:global_overview/services/translate_service.dart';
import 'package:global_overview/services/word_service.dart';

import 'fake_db.dart';

class _Db extends FakeDb {
  final List<String> writes = [];
  Object? cached;

  @override
  Future<List<Map<String, dynamic>>> select(String sql, [List<Object?>? params]) async {
    if (sql.contains('FROM word_cache')) return cached == null ? [] : [<String, dynamic>{'result': cached}];
    return [];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? params]) async {
    writes.add(sql);
    if (sql.contains('INSERT OR REPLACE INTO word_cache')) cached = params?[2];
  }
}

class _FakeTranslate extends TranslateService {
  _FakeTranslate() : super(HttpService(), AppConfigService(), LlmService(HttpService(), AppConfigService()));
  int calls = 0;
  String result = '';
  Object? error;

  @override
  Future<String> translate(String text, {String from = 'en', String to = 'zh'}) async {
    calls++;
    final e = error;
    if (e != null) throw e;
    return result;
  }
}

void main() {
  test('翻译失败时不写缓存，并进入负缓存', () async {
    final db = _Db();
    final tr = _FakeTranslate()..error = StateError('boom');
    final svc = WordService(db, tr);

    expect(await svc.lookup('privacy'), '');
    expect(await svc.lookup('privacy'), '');
    expect(tr.calls, 1, reason: '60 秒内不应重复打接口');
    expect(db.writes.where((w) => w.contains('word_cache')), isEmpty);
  });

  test('翻译返回原文视为失败', () async {
    final db = _Db();
    final tr = _FakeTranslate()..result = 'privacy';
    final svc = WordService(db, tr);
    expect(await svc.lookup('privacy'), '');
    expect(db.writes.where((w) => w.contains('word_cache')), isEmpty);
  });

  test('成功时写入缓存并直接命中', () async {
    final db = _Db();
    final tr = _FakeTranslate()..result = '隐私';
    final svc = WordService(db, tr);
    expect(await svc.lookup('privacy'), '隐私');
    expect(await svc.lookup('privacy'), '隐私');
    expect(tr.calls, 1);
    expect(db.writes.where((w) => w.contains('word_cache')).length, 1);
  });

  test('历史遗留的空缓存会被视为未命中并重试', () async {
    final db = _Db()..cached = '';
    final tr = _FakeTranslate()..result = '隐私';
    final svc = WordService(db, tr);
    expect(await svc.lookup('privacy'), '隐私');
    expect(tr.calls, 1);
  });
}