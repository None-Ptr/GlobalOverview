import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LlmProfile {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;
  LlmProfile({required this.id, required this.name, required this.baseUrl, required this.apiKey, required this.model});
  factory LlmProfile.fromJson(Map<String, dynamic> j) => LlmProfile(
        id: j['id'], name: j['name'], baseUrl: j['baseUrl'], apiKey: j['apiKey'], model: j['model']);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'baseUrl': baseUrl, 'apiKey': apiKey, 'model': model};
}

class TranslateConfig {
  final String baiduAppId;
  final String baiduKey;
  TranslateConfig({this.baiduAppId = '', this.baiduKey = ''});
  factory TranslateConfig.fromJson(Map<String, dynamic> j) => TranslateConfig(baiduAppId: j['baiduAppId'] ?? '', baiduKey: j['baiduKey'] ?? '');
  Map<String, dynamic> toJson() => {'baiduAppId': baiduAppId, 'baiduKey': baiduKey};
}

/// 自定义翻译接口（对齐 customTranslate.js 的存储项）。
class CustomTranslator {
  final String id;
  final String name;
  final String url;
  final String method;
  final String headers;
  final String body;
  final String resultPath;
  final String langMap;
  CustomTranslator({required this.id, required this.name, required this.url, this.method = 'POST', this.headers = '', this.body = '', this.resultPath = 'data.translation', this.langMap = ''});
  factory CustomTranslator.fromJson(Map<String, dynamic> j) => CustomTranslator(
        id: '${j['id']}', name: j['name'] ?? '', url: j['url'] ?? '', method: j['method'] ?? 'POST',
        headers: j['headers'] ?? '', body: j['body'] ?? '', resultPath: j['resultPath'] ?? 'data.translation', langMap: j['langMap'] ?? '');
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'url': url, 'method': method, 'headers': headers, 'body': body, 'resultPath': resultPath, 'langMap': langMap};
}

class AppConfigService extends ChangeNotifier {
  static final _builtinFree = LlmProfile(
    id: 'builtin_free',
    name: 'GLM-4.7-Flash',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    apiKey: 'dc0fd1de95b9ffc7e3b86e2f3d8c4a3e',
    model: 'glm-4.7-flash',
  );

  SharedPreferences? _prefs;
  bool _secureOk = !Platform.environment.containsKey('FLUTTER_TEST');
  List<LlmProfile> _profiles = [];
  String _currentProfileId = _builtinFree.id;
  TranslateConfig _translate = TranslateConfig();
  bool _darkMode = true;
  int _dailyGoal = 0;
  // 阅读设置（对齐 store.reader）
  double _fontSize = 18;
  double _lineHeight = 1.8;
  String _transEngine = 'auto';
  String _userAgent = '';
  String _extraHeaders = '';

  static const defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static const _kProfiles = 'llm_profiles';
  static const _kCurrent = 'llm_current';
  static const _kTranslate = 'translate';
  static const _kTranslators = 'custom_translators';
  static const _kUa = 'fetch_user_agent';
  static const _kExtraHeaders = 'fetch_extra_headers';

  static const _sProfiles = 'llm_profiles_v2';
  static const _sTranslate = 'translate_v2';
  static const _sTranslators = 'custom_translators_v2';
  static const _sExtraHeaders = 'fetch_extra_headers_v2';

  static const _secure = FlutterSecureStorage(aOptions: AndroidOptions());

  List<LlmProfile> get profiles => _profiles;
  String get currentProfileId => _currentProfileId;
  LlmProfile get currentProfile => _profiles.firstWhere((p) => p.id == _currentProfileId, orElse: () => _builtinFree);
  TranslateConfig get translate => _translate;
  bool get darkMode => _darkMode;
  int get dailyGoal => _dailyGoal;
  double get fontSize => _fontSize;
  double get lineHeight => _lineHeight;
  String get transEngine => _transEngine;

  List<CustomTranslator> _translators = [];
  List<CustomTranslator> get translators => _translators;
  String get userAgent => _userAgent;
  String get extraHeaders => _extraHeaders;
  String get effectiveUserAgent => _userAgent.trim().isEmpty ? defaultUserAgent : _userAgent.trim();

  /// 抓取链路（RSS 列表 / 文章正文 / 图片）用的请求头；LLM 与翻译接口不经过这里。
  Map<String, String> fetchHeadersFor(String url) {
    final out = <String, String>{
      'User-Agent': effectiveUserAgent,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
    };
    final raw = _extraHeaders.trim();
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(_fill(raw, url));
        if (decoded is Map) {
          decoded.forEach((k, v) {
            final key = '$k'.trim();
            if (key.isNotEmpty) out[key] = '$v';
          });
        }
      } catch (_) {}
    }
    return out;
  }

  static String _fill(String tpl, String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return tpl.replaceAll('{url}', url).replaceAll('{host}', host);
  }

  Future<void> setFetchOptions({String? userAgent, String? extraHeaders}) async {
    if (userAgent != null) {
      _userAgent = userAgent;
      await _prefs?.setString(_kUa, userAgent);
    }
    if (extraHeaders != null) {
      _extraHeaders = extraHeaders;
      await _writeSecret(_sExtraHeaders, _kExtraHeaders, extraHeaders);
    }
    notifyListeners();
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _migrate(_sProfiles, _kProfiles);
    await _migrate(_sTranslate, _kTranslate);
    await _migrate(_sTranslators, _kTranslators);
    await _migrate(_sExtraHeaders, _kExtraHeaders);
    final rawProfiles = await _readSecret(_sProfiles, _kProfiles);
    if (rawProfiles != null) {
      try {
        final list = (jsonDecode(rawProfiles) as List).map((e) => LlmProfile.fromJson(e)).toList();
        _profiles = list.isNotEmpty ? list : [_builtinFree];
      } catch (_) {
        _profiles = [_builtinFree];
      }
    } else {
      _profiles = [_builtinFree];
    }
    final rawCurrent = _prefs!.getString(_kCurrent);
    if (rawCurrent != null) _currentProfileId = rawCurrent;
    if (!_profiles.any((p) => p.id == _currentProfileId)) _currentProfileId = _profiles.first.id;
    final rawT = await _readSecret(_sTranslate, _kTranslate);
    if (rawT != null) {
      try {
        _translate = TranslateConfig.fromJson(jsonDecode(rawT));
      } catch (_) {}
    }
    _darkMode = _prefs!.getBool('dark_mode') ?? true;
    _dailyGoal = _prefs!.getInt('daily_goal') ?? 0;
    _fontSize = _prefs!.getDouble('reader_fontSize') ?? 18;
    _lineHeight = _prefs!.getDouble('reader_lineHeight') ?? 1.8;
    _transEngine = _prefs!.getString('reader_transEngine') ?? 'auto';
    _userAgent = _prefs!.getString(_kUa) ?? '';
    _extraHeaders = await _readSecret(_sExtraHeaders, _kExtraHeaders) ?? '';
    final rawTr = await _readSecret(_sTranslators, _kTranslators);
    if (rawTr != null) {
      try {
        _translators = (jsonDecode(rawTr) as List).map((e) => CustomTranslator.fromJson(Map<String, dynamic>.from(e))).toList();
      } catch (_) {
        _translators = [];
      }
    }
  }

  Future<void> _saveProfiles() =>
      _writeSecret(_sProfiles, _kProfiles, jsonEncode(_profiles.map((e) => e.toJson()).toList()));

  Future<String?> _readSecret(String secureKey, String legacyKey) async {
    if (_secureOk) {
      try {
        final v = await _secure.read(key: secureKey);
        if (v != null) return v;
      } catch (_) {
        _secureOk = false;
      }
    }
    return _prefs?.getString(legacyKey);
  }

  Future<void> _writeSecret(String secureKey, String legacyKey, String value) async {
    if (_secureOk) {
      try {
        await _secure.write(key: secureKey, value: value);
        await _prefs?.remove(legacyKey);
        return;
      } catch (_) {
        _secureOk = false;
      }
    }
    await _prefs?.setString(legacyKey, value);
  }

  /// 明文 → Keystore：确认加密写入成功后才删明文，避免密钥丢失。
  Future<void> _migrate(String secureKey, String legacyKey) async {
    final legacy = _prefs?.getString(legacyKey);
    if (legacy == null || !_secureOk) return;
    try {
      if (await _secure.read(key: secureKey) != null) {
        await _prefs?.remove(legacyKey);
        return;
      }
      await _secure.write(key: secureKey, value: legacy);
      if (await _secure.read(key: secureKey) != null) await _prefs?.remove(legacyKey);
    } catch (_) {
      _secureOk = false;
    }
  }
  Future<void> setProfiles(List<LlmProfile> list) async {
    _profiles = list.isNotEmpty ? list : [_builtinFree];
    await _saveProfiles();
    notifyListeners();
  }
  Future<void> setCurrentProfile(String id) async {
    _currentProfileId = id;
    await _prefs!.setString(_kCurrent, id);
    notifyListeners();
  }
  Future<void> setDarkMode(bool v) async {
    _darkMode = v;
    await _prefs!.setBool('dark_mode', v);
    notifyListeners();
  }
  Future<void> setDailyGoal(int v) async {
    _dailyGoal = v;
    await _prefs!.setInt('daily_goal', v);
    notifyListeners();
  }

  Future<void> setReader({double? fontSize, double? lineHeight, String? transEngine}) async {
    if (fontSize != null) {
      _fontSize = fontSize;
      await _prefs!.setDouble('reader_fontSize', fontSize);
    }
    if (lineHeight != null) {
      _lineHeight = lineHeight;
      await _prefs!.setDouble('reader_lineHeight', lineHeight);
    }
    if (transEngine != null) {
      _transEngine = transEngine;
      await _prefs!.setString('reader_transEngine', transEngine);
    }
    notifyListeners();
  }

  Future<void> upsertTranslator(CustomTranslator t) async {
    final i = _translators.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      _translators[i] = t;
    } else {
      _translators.add(t);
    }
    await _writeSecret(_sTranslators, _kTranslators, jsonEncode(_translators.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  Future<void> deleteTranslator(String id) async {
    _translators.removeWhere((x) => x.id == id);
    await _writeSecret(_sTranslators, _kTranslators, jsonEncode(_translators.map((e) => e.toJson()).toList()));
    notifyListeners();
  }
}
