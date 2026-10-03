import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/translate_service.dart';

class WordService {
  final DbService _db;
  final TranslateService _translate;
  WordService(this._db, this._translate);

  static const _failTtlMs = 60000;
  final Map<String, int> _failedAt = {};

  Future<String> lookup(String word, {String mode = 'en2zh'}) async {
    final lemma = word.toLowerCase().trim();
    final key = '$lemma@$mode';
    final exist = await _db.select('SELECT result FROM word_cache WHERE word = ? AND mode = ?', [lemma, mode]);
    final cached = exist.isEmpty ? null : exist.first['result'] as String?;
    if (cached != null && cached.trim().isNotEmpty) return cached;

    final now = DateTime.now().millisecondsSinceEpoch;
    final failedAt = _failedAt[key];
    if (failedAt != null && now - failedAt < _failTtlMs) return '';

    String zh;
    try {
      zh = await _translate.translate(word, from: 'en', to: 'zh');
    } catch (_) {
      _failedAt[key] = now;
      return '';
    }
    if (zh.trim().isEmpty || zh.trim() == word.trim()) {
      _failedAt[key] = now;
      return '';
    }
    _failedAt.remove(key);
    await _db.execute('INSERT OR REPLACE INTO word_cache (word, mode, result, at, lemma) VALUES (?,?,?,?,?)',
        [lemma, mode, zh, DateTime.now().millisecondsSinceEpoch, lemma]);
    return zh;
  }
}
