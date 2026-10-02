import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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
  List<LlmProfile> _profiles = [];
  String _currentProfileId = _builtinFree.id;
  TranslateConfig _translate = TranslateConfig();
  bool _darkMode = true;
  int _dailyGoal = 0;
  // 阅读设置（对齐 store.reader）
  double _fontSize = 18;
  double _lineHeight = 1.8;
  String _transEngine = 'auto';

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

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final rawProfiles = _prefs!.getString('llm_profiles');
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
    if (_prefs!.getString('llm_current') != null) _currentProfileId = _prefs!.getString('llm_current')!;
    if (!_profiles.any((p) => p.id == _currentProfileId)) _currentProfileId = _profiles.first.id;
    final rawT = _prefs!.getString('translate');
    if (rawT != null) _translate = TranslateConfig.fromJson(jsonDecode(rawT));
    _darkMode = _prefs!.getBool('dark_mode') ?? true;
    _dailyGoal = _prefs!.getInt('daily_goal') ?? 0;
    _fontSize = _prefs!.getDouble('reader_fontSize') ?? 18;
    _lineHeight = _prefs!.getDouble('reader_lineHeight') ?? 1.8;
    _transEngine = _prefs!.getString('reader_transEngine') ?? 'auto';
    final rawTr = _prefs!.getString('custom_translators');
    if (rawTr != null) {
      try {
        _translators = (jsonDecode(rawTr) as List).map((e) => CustomTranslator.fromJson(Map<String, dynamic>.from(e))).toList();
      } catch (_) {
        _translators = [];
      }
    }
  }

  Future<void> _saveProfiles() => _prefs!.setString('llm_profiles', jsonEncode(_profiles.map((e) => e.toJson()).toList()));
  Future<void> setProfiles(List<LlmProfile> list) async {
    _profiles = list.isNotEmpty ? list : [_builtinFree];
    await _saveProfiles();
    notifyListeners();
  }
  Future<void> setCurrentProfile(String id) async {
    _currentProfileId = id;
    await _prefs!.setString('llm_current', id);
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
    await _prefs!.setString('custom_translators', jsonEncode(_translators.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  Future<void> deleteTranslator(String id) async {
    _translators.removeWhere((x) => x.id == id);
    await _prefs!.setString('custom_translators', jsonEncode(_translators.map((e) => e.toJson()).toList()));
    notifyListeners();
  }
}
