import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/llm_service.dart';

class TranslateService {
  final HttpService _http;
  final AppConfigService _cfg;
  final LlmService _llm;
  TranslateService(this._http, this._cfg, this._llm);

  /// 翻译引擎 id → 显示名（对齐 translate.js 的 getEngineNames）。
  static const engineNames = <String, String>{
    'auto': '自动',
    'baidu': '百度',
    'mymemory': 'MyMemory',
    'libre': 'LibreTranslate',
    'llm': '大模型',
  };

  Future<String> translate(String text, {String from = 'en', String to = 'zh'}) async {
    if (text.trim().isEmpty) return '';
    final engine = _cfg.transEngine;
    switch (engine) {
      case 'baidu':
        return (await _baidu(text, from, to)) ?? _llmFallback(text, from, to);
      case 'mymemory':
        return (await _myMemory(text, from, to)) ?? _llmFallback(text, from, to);
      case 'libre':
        return (await _libre(text, from, to)) ?? _llmFallback(text, from, to);
      case 'llm':
        return _llmFallback(text, from, to);
      case 'auto':
        break;
      default:
        final ct = _cfg.translators.where((t) => t.id == engine).toList();
        if (ct.isNotEmpty) {
          final out = await _custom(ct.first, text, from, to);
          if (out != null && out.isNotEmpty) return out;
        }
        return _llmFallback(text, from, to);
    }
    final baidu = await _baidu(text, from, to);
    if (baidu != null) return baidu;
    final my = await _myMemory(text, from, to);
    if (my != null) return my;
    final libre = await _libre(text, from, to);
    if (libre != null) return libre;
    return _llmFallback(text, from, to);
  }

  Future<String> _llmFallback(String text, String from, String to) async {
    try {
      return await _llm.chat('You are a translator. Translate the text between the markers from $from to $to. Output only the translation.', text);
    } catch (_) {
      return text;
    }
  }

  Future<String?> _custom(CustomTranslator t, String text, String from, String to) async {
    try {
      final target = _mapLang(t.langMap, to) ?? to;
      final source = _mapLang(t.langMap, from) ?? from;
      String sub(String s) => s.replaceAll('{text}', text).replaceAll('{target}', target).replaceAll('{lang}', target).replaceAll('{source}', source);
      Map<String, String>? headers;
      if (t.headers.trim().isNotEmpty) {
        try {
          final h = jsonDecode(sub(t.headers));
          if (h is Map) headers = h.map((k, v) => MapEntry('$k', '$v'));
        } catch (_) {}
      }
      dynamic res;
      if (t.method.toUpperCase() == 'GET') {
        res = await _http.getJson(sub(t.url), headers: headers);
      } else {
        Map<String, dynamic> body;
        try {
          body = t.body.trim().isEmpty
              ? {'q': text, 'target': target, 'source': source}
              : Map<String, dynamic>.from(jsonDecode(sub(t.body)) as Map);
        } catch (_) {
          body = {'q': text, 'target': target, 'source': source};
        }
        res = await _http.postJson(sub(t.url), body, headers: headers);
      }
      final out = _extract(res, t.resultPath);
      final s = out?.toString() ?? '';
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  String? _mapLang(String langMap, String code) {
    if (langMap.trim().isEmpty) return null;
    try {
      final m = jsonDecode(langMap);
      if (m is Map) {
        final v = m[code.toUpperCase()] ?? m[code];
        if (v != null) return '$v';
      }
    } catch (_) {}
    return null;
  }

  dynamic _extract(dynamic res, String path) {
    if (path.trim().isEmpty) return res;
    dynamic cur = res;
    for (final seg in path.split('.')) {
      if (cur is Map && cur.containsKey(seg)) {
        cur = cur[seg];
      } else {
        return cur;
      }
    }
    return cur;
  }

  Future<String?> _myMemory(String text, String from, String to) async {
    try {
      final res = await _http.getJson('https://api.mymemory.translated.net/get?q=${Uri.encodeComponent(text)}&langpair=$from|$to');
      final out = res['responseData']?['translatedText'] as String?;
      if (out != null && out.isNotEmpty && !out.toLowerCase().contains('mymemory')) return out;
    } catch (_) {}
    return null;
  }

  Future<String?> _libre(String text, String from, String to) async {
    try {
      final res = await _http.postJson('https://libretranslate.com/translate', {'q': text, 'source': from, 'target': to, 'format': 'text'});
      final out = res['translatedText'] as String?;
      if (out != null && out.isNotEmpty) return out;
    } catch (_) {}
    return null;
  }

  Future<String?> _baidu(String text, String from, String to) async {
    final cfg = _cfg.translate;
    if (cfg.baiduAppId.isEmpty || cfg.baiduKey.isEmpty) return null;
    try {
      final salt = DateTime.now().millisecondsSinceEpoch.toString();
      final sign = md5.convert(utf8.encode('${cfg.baiduAppId}$text$salt${cfg.baiduKey}')).toString();
      final res = await _http.getJson(
          'https://fanyi-api.baidu.com/api/trans/vip/translate?q=${Uri.encodeComponent(text)}&from=$from&to=$to&appid=${cfg.baiduAppId}&salt=$salt&sign=$sign');
      final list = res['trans_result'] as List?;
      final out = list?.map((e) => e['dst']).join('\n');
      if (out != null && out.isNotEmpty) return out;
    } catch (_) {}
    return null;
  }
}
