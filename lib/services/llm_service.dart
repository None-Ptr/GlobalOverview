import 'dart:convert';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/app_config_service.dart';

class LlmService {
  final HttpService _http;
  final AppConfigService _cfg;
  LlmService(this._http, this._cfg);

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
    final res = await _http.postJson(url, body, headers: {'Authorization': 'Bearer ${p.apiKey}'});
    final choices = res['choices'];
    if (choices is! List || choices.isEmpty) {
      final err = res['error'];
      final msg = err is Map ? (err['message'] ?? '$err') : (res['message'] ?? '$res');
      throw Exception('LLM 接口未返回内容: $msg');
    }
    final first = choices[0];
    if (first is! Map || first['message'] is! Map) {
      throw Exception('LLM 响应格式异常: $first');
    }
    return ((first['message'] as Map)['content'] ?? '') as String;
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
