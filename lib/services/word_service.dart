import 'package:global_overview/services/db_service.dart';
import 'package:global_overview/services/translate_service.dart';

class WordService {
  final DbService _db;
  final TranslateService _translate;
  WordService(this._db, this._translate);

  Future<String> lookup(String word, {String mode = 'en2zh'}) async {
    final lemma = word.toLowerCase().trim();
    final exist = await _db.select('SELECT result FROM word_cache WHERE word = ? AND mode = ?', [lemma, mode]);
    if (exist.isNotEmpty && exist.first['result'] != null) return exist.first['result'] as String;
    final zh = await _translate.translate(word, from: 'en', to: 'zh');
    await _db.execute('INSERT OR REPLACE INTO word_cache (word, mode, result, at, lemma) VALUES (?,?,?,?,?)',
        [lemma, mode, zh, DateTime.now().millisecondsSinceEpoch, lemma]);
    return zh;
  }
}
