import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/llm_service.dart';

LlmService _service(http.Client client) => LlmService(HttpService(client: client), AppConfigService());

String _reply(String content) => '{"choices":[{"message":{"content":"$content"}}]}';

void main() {
  test('401 变成可操作的提示', () async {
    final svc = _service(MockClient((req) async => http.Response('{"error":{"message":"invalid key"}}', 401)));
    await expectLater(
      svc.chat('s', 'u'),
      throwsA(isA<AppException>()
          .having((e) => e.code, 'code', 'llmKey')
          .having((e) => e.message, 'message', contains('api key'))),
    );
  });

  test('404 提示检查 base url', () async {
    final svc = _service(MockClient((req) async => http.Response('not found', 404)));
    await expectLater(svc.chat('s', 'u'), throwsA(isA<AppException>().having((e) => e.code, 'code', 'llmUrl')));
  });

  test('429 归类为限流且会重试', () async {
    var calls = 0;
    final svc = _service(MockClient((req) async {
      calls++;
      return http.Response('{"error":"rate limit"}', 429);
    }));
    await expectLater(svc.chat('s', 'u'), throwsA(isA<AppException>().having((e) => e.code, 'code', 'llmRate')));
    expect(calls, greaterThan(1));
  });

  test('返回 HTML 时是 llmFormat 而不是 FormatException', () async {
    final svc = _service(MockClient((req) async => http.Response('<html>502 Bad Gateway</html>', 200)));
    await expectLater(svc.chat('s', 'u'), throwsA(isA<AppException>().having((e) => e.code, 'code', 'llmFormat')));
  });

  test('空 content 视为失败', () async {
    final svc = _service(MockClient((req) async => http.Response(_reply(''), 200)));
    await expectLater(svc.chat('s', 'u'), throwsA(isA<AppException>().having((e) => e.code, 'code', 'llmEmpty')));
  });

  test('缺 content 字段也视为失败', () async {
    final svc = _service(MockClient((req) async => http.Response('{"choices":[{"message":{}}]}', 200)));
    await expectLater(svc.chat('s', 'u'), throwsA(isA<AppException>().having((e) => e.code, 'code', 'llmEmpty')));
  });

  test('正常返回内容', () async {
    final svc = _service(MockClient((req) async => http.Response(_reply('hello'), 200)));
    expect(await svc.chat('s', 'u'), 'hello');
  });
}