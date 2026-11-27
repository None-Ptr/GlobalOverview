import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/app_exception.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/llm_service.dart';
import 'package:global_overview/v4/services/ai_cost_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ThrowingHttp extends HttpService {
  @override
  Future<Map<String, dynamic>> postJson(
    String url,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    RetryPolicy retry = RetryPolicy.none,
    Duration? timeout,
  }) async => throw const AppException('network', '网络请求失败');
}

class _FakeHttp extends HttpService {
  final Map<String, dynamic> response;
  _FakeHttp(this.response);

  @override
  Future<Map<String, dynamic>> postJson(
    String url,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    RetryPolicy retry = RetryPolicy.none,
    Duration? timeout,
  }) async => response;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('一次模型调用会在用量账本里留一条记录', () async {
    SharedPreferences.setMockInitialValues({});
    final llm = LlmService(
      _FakeHttp({
        'choices': [
          {
            'message': {'content': '好的'},
          },
        ],
        'usage': {'prompt_tokens': 1200, 'completion_tokens': 300},
      }),
      AppConfigService(),
    );

    await llm.chat('system', 'user', operation: '生成练习');

    final rows = await AiUsageLedger().list();
    expect(rows.length, 1);
    expect(rows.single.operation, '生成练习');
    expect(rows.single.inputTokens, 1200);
    expect(rows.single.outputTokens, 300);
    expect(rows.single.model, isNotEmpty);
    expect(rows.single.at, greaterThan(0));
    // The built-in model has a local price of zero, so the amount is known.
    expect(rows.single.amount, isNotNull);
  });

  test('接口不给 usage 时用估算与字数兜底，仍然记账', () async {
    SharedPreferences.setMockInitialValues({});
    final llm = LlmService(
      _FakeHttp({
        'choices': [
          {
            'message': {'content': 'x' * 400},
          },
        ],
      }),
      AppConfigService(),
    );

    await llm.chat('system', 'user', operation: '判分');

    final rows = await AiUsageLedger().list();
    expect(rows.length, 1);
    expect(rows.single.inputTokens, greaterThan(0));
    expect(rows.single.outputTokens, 100);
  });

  test('网络失败记为失败行，不计金额', () async {
    SharedPreferences.setMockInitialValues({});
    final llm = LlmService(_ThrowingHttp(), AppConfigService());

    await expectLater(
      llm.chat('system', 'user', operation: '判分'),
      throwsA(isA<AppException>()),
    );

    final rows = await AiUsageLedger().list();
    expect(rows.single.status, 'failed');
    expect(rows.single.amount, isNull);
    expect(rows.single.durationMs, greaterThanOrEqualTo(0));
  });

  test('模型返回空内容时不写用量', () async {
    SharedPreferences.setMockInitialValues({});
    final llm = LlmService(
      _FakeHttp({
        'choices': [],
      }),
      AppConfigService(),
    );

    await expectLater(llm.chat('system', 'user'), throwsA(isA<Exception>()));
    expect(await AiUsageLedger().list(), isEmpty);
  });
}
