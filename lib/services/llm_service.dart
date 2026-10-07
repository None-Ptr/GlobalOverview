import 'dart:convert';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/app_exception.dart';

class LlmService {
  final HttpService _http;
  final AppConfigService _cfg;
  LlmService(this._http, this._cfg);

  /// 送进 prompt 的正文上限（字符）。约等于 3k token 的英文，超出部分多数模型会直接报错或静默截断。
  static const int maxPromptChars = 12000;

  /// 截断过长正文。优先在段落边界断开，避免只切半句话导致题目失真。
  static String clipArticle(String text, {int limit = maxPromptChars}) {
    if (text.length <= limit) return text;
    final cut = text.substring(0, limit);
    final br = cut.lastIndexOf('\n');
    return (br > limit ~/ 2 ? cut.substring(0, br) : cut).trim();
  }

  Future<String> chat(String system, String user, {double temperature = 0.7}) async {
    final p = _cfg.currentProfile;
    final url = '${p.baseUrl}/chat/completions';
    final body = {
      'model': p.model,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'temperature': temperature,
    };
    final Map<String, dynamic> res;
    try {
      res = await _http.postJson(url, body, headers: {'Authorization': 'Bearer ${p.apiKey}'}, retry: RetryPolicy.manual);
    } on AppException catch (e) {
      throw _readable(e, p);
    }
    final choices = res['choices'];
    if (choices is! List || choices.isEmpty) {
      final err = res['error'];
      final msg = err is Map ? (err['message'] ?? '$err') : (res['message'] ?? '$res');
      throw AppException('llmEmpty', '模型没有返回内容', detail: '$msg');
    }
    final first = choices.first;
    if (first is! Map || first['message'] is! Map) {
      throw AppException('llmFormat', '模型返回格式异常', detail: '$first');
    }
    final content = ((first['message'] as Map)['content'] ?? '').toString().trim();
    if (content.isEmpty) {
      throw AppException('llmEmpty', '模型返回了空内容', detail: 'choices[0].message.content 为空');
    }
    return content;
  }

  AppException _readable(AppException e, LlmProfile p) {
    switch (e.code) {
      case 'http401':
        return AppException('llmKey', 'api key 无效或已失效（401），请在「我的 → LLM 模型」里检查', detail: e.detail, status: e.status);
      case 'http403':
        return AppException('llmKey', '接口拒绝访问（403），请在「我的 → LLM 模型」里检查 key 与 base url', detail: e.detail, status: e.status);
      case 'http404':
        return AppException('llmUrl', '接口地址不存在（404），请检查 base url 是否写全', detail: e.detail, status: e.status);
      case 'http429':
        return AppException('llmRate', '模型接口被限流（429），内置模型是共享额度，建议配置自己的模型', detail: e.detail, status: e.status, retryable: true);
      case 'badJson':
      case 'emptyBody':
        return AppException('llmFormat', '模型返回的不是预期内容', detail: e.detail);
    }
    if (e.retryable) {
      return AppException(e.code, '${e.message}（模型：${p.name}）', detail: e.detail, status: e.status, retryable: true);
    }
    return e;
  }

  Future<dynamic> structured(String system, String user, {double temperature = 0.3}) async {
    final raw = await chat(system, '$user\n只输出 JSON，不要任何解释或 Markdown 代码块。', temperature: temperature);
    return _decode(raw);
  }

  dynamic _decode(String raw) {
    final start = raw.indexOf(RegExp(r'[\{\[]'));
    final end = raw.lastIndexOf(RegExp(r'[\}\]]'));
    if (start >= 0 && end > start) {
      return jsonDecode(raw.substring(start, end + 1));
    }
    return jsonDecode(raw);
  }
}
