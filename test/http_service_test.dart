import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/services/http_service.dart';

Future<AppConfigService> _config({String ua = '', String extra = ''}) async {
  SharedPreferences.setMockInitialValues({});
  final cfg = AppConfigService();
  await cfg.init();
  await cfg.setFetchOptions(userAgent: ua, extraHeaders: extra);
  return cfg;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('抓取请求带内置默认 UA，且附加头支持 {url}/{host} 占位符', () async {
    late http.Request seen;
    final svc = HttpService(
      client: MockClient((req) async {
        seen = req;
        return http.Response('<html><body>ok</body></html>', 200);
      }),
      config: await _config(ua: 'MyUA/1.0', extra: '{"Referer":"{url}","X-Host":"{host}"}'),
    );

    await svc.getText('https://example.com/a/b');

    expect(seen.headers['User-Agent'], 'MyUA/1.0');
    expect(seen.headers['Referer'], 'https://example.com/a/b');
    expect(seen.headers['X-Host'], 'example.com');
    expect(seen.headers['Accept'], isNotEmpty);
  });

  test('未配置时使用内置默认 UA', () async {
    late http.Request seen;
    final svc = HttpService(
      client: MockClient((req) async {
        seen = req;
        return http.Response('ok', 200);
      }),
      config: await _config(),
    );
    await svc.getText('https://example.com/');
    expect(seen.headers['User-Agent'], AppConfigService.defaultUserAgent);
  });

  test('附加头不是合法 JSON 时静默忽略，不影响请求', () async {
    late http.Request seen;
    final svc = HttpService(
      client: MockClient((req) async {
        seen = req;
        return http.Response('ok', 200);
      }),
      config: await _config(extra: 'not-json'),
    );
    await svc.getText('https://example.com/');
    expect(seen.headers['User-Agent'], AppConfigService.defaultUserAgent);
  });

  test('接口请求（LLM/翻译）不带 UA', () async {
    late http.Request seen;
    final svc = HttpService(
      client: MockClient((req) async {
        seen = req;
        return http.Response('{"ok":true}', 200, headers: {'content-type': 'application/json'});
      }),
      config: await _config(ua: 'MyUA/1.0'),
    );
    await svc.getJson('https://api.example.com/v1/models');
    expect(seen.headers.containsKey('user-agent'), isFalse);
    expect(seen.headers['Accept'], 'application/json');
  });

  test('403 不重试并给出可读原因', () async {
    var calls = 0;
    final svc = HttpService(
      client: MockClient((req) async {
        calls++;
        return http.Response('forbidden', 403);
      }),
    );
    await expectLater(
      svc.getText('https://example.com/', retry: const RetryPolicy(attempts: 3, backoff: [Duration.zero, Duration.zero])),
      throwsA(isA<AppException>()
          .having((e) => e.code, 'code', 'http403')
          .having((e) => e.retryable, 'retryable', isFalse)),
    );
    expect(calls, 1);
  });

  test('429 会按策略重试', () async {
    var calls = 0;
    final svc = HttpService(
      client: MockClient((req) async {
        calls++;
        return http.Response('slow down', 429);
      }),
    );
    await expectLater(
      svc.getText('https://example.com/', retry: const RetryPolicy(attempts: 2, backoff: [Duration.zero])),
      throwsA(isA<AppException>().having((e) => e.code, 'code', 'http429')),
    );
    expect(calls, 2);
  });

  test('5xx 第一次失败、重试成功', () async {
    var calls = 0;
    final svc = HttpService(
      client: MockClient((req) async {
        calls++;
        if (calls == 1) return http.Response('oops', 503);
        return http.Response('recovered', 200);
      }),
    );
    final body = await svc.getText('https://example.com/', retry: const RetryPolicy(attempts: 3, backoff: [Duration.zero]));
    expect(body, 'recovered');
    expect(calls, 2);
  });

  test('401/404 不重试', () async {
    for (final code in [401, 404]) {
      var calls = 0;
      final svc = HttpService(
        client: MockClient((req) async {
          calls++;
          return http.Response('nope', code);
        }),
      );
      await expectLater(
        svc.getText('https://example.com/', retry: const RetryPolicy(attempts: 3, backoff: [Duration.zero])),
        throwsA(isA<AppException>()),
      );
      expect(calls, 1, reason: '$code 不应重试');
    }
  });

  test('超出时间预算时直接放弃', () async {
    var calls = 0;
    final svc = HttpService(
      client: MockClient((req) async {
        calls++;
        return http.Response('x', 503);
      }),
    );
    await expectLater(
      svc.getText('https://example.com/', retry: RetryPolicy.until(DateTime.now().subtract(const Duration(seconds: 1)))),
      throwsA(isA<AppException>().having((e) => e.code, 'code', 'deadline')),
    );
    expect(calls, 0);
  });

  test('200 但空 body 视为失败', () async {
    final svc = HttpService(client: MockClient((req) async => http.Response('', 200)));
    await expectLater(
      svc.getText('https://example.com/'),
      throwsA(isA<AppException>().having((e) => e.code, 'code', 'emptyBody')),
    );
  });

  test('按 content-type 的 charset 解码，非 UTF-8 不再抛异常', () async {
    final svc = HttpService(client: MockClient((req) async {
      return http.Response.bytes(
        [0x63, 0x61, 0x66, 0xE9],
        200,
        headers: {'content-type': 'text/html; charset=ISO-8859-1'},
      );
    }));
    expect(await svc.getText('https://example.com/'), 'café');

    final svc2 = HttpService(client: MockClient((req) async {
      return http.Response.bytes([0x63, 0x61, 0x66, 0xE9], 200, headers: {'content-type': 'text/html'});
    }));
    expect(await svc2.getText('https://example.com/'), isNot(throwsA(anything)));
  });

  test('JSON 接口返回 HTML 时给出可读错误而不是 FormatException', () async {
    final svc = HttpService(client: MockClient((req) async => http.Response('<!DOCTYPE html><html>502</html>', 200)));
    await expectLater(
      svc.getJson('https://api.example.com/chat'),
      throwsA(isA<AppException>().having((e) => e.code, 'code', 'badJson')),
    );
  });

  test('约定的重试参数被固定下来', () {
    expect(RetryPolicy.batch.attempts, 2);
    expect(RetryPolicy.batch.backoff, [const Duration(milliseconds: 800)]);
    expect(RetryPolicy.manual.attempts, 3);
    expect(RetryPolicy.manual.backoff, [const Duration(milliseconds: 500), Duration(seconds: 1), Duration(seconds: 2)]);
    expect(RetryPolicy.none.attempts, 1);
  });
}
