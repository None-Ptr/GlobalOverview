import 'dart:convert';
import 'package:http/http.dart' as http;

class HttpService {
  static const _timeout = Duration(seconds: 20);

  Future<String> getText(String url, {Map<String, String>? headers}) async {
    final res = await http.get(Uri.parse(url), headers: headers).timeout(_timeout);
    return _decodeBody(res);
  }

  Future<Map<String, dynamic>> getJson(String url, {Map<String, String>? headers}) async {
    final res = await http.get(Uri.parse(url), headers: _jsonHeaders(headers)).timeout(_timeout);
    return jsonDecode(_decodeBody(res)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> postJson(String url, Map<String, dynamic> body, {Map<String, String>? headers}) async {
    final res = await http
        .post(Uri.parse(url), headers: _jsonHeaders(headers), body: jsonEncode(body))
        .timeout(_timeout);
    return jsonDecode(_decodeBody(res)) as Map<String, dynamic>;
  }

  String _decodeBody(http.Response res) {
    final charset = _encodingFromHeader(res.headers['content-type']);
    if (charset != null && charset.toLowerCase() != 'utf-8') {
      try {
        return utf8.decode(res.bodyBytes);
      } catch (_) {}
    }
    return utf8.decode(res.bodyBytes);
  }

  String? _encodingFromHeader(String? ct) {
    if (ct == null) return null;
    final m = RegExp(r'charset=([\w-]+)', caseSensitive: false).firstMatch(ct);
    return m?.group(1);
  }

  Map<String, String> _jsonHeaders(Map<String, String>? extra) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        ...?extra,
      };
}
