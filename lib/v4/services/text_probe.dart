/// Character-level probes behind the reader's tap-a-word and grab-a-sentence
/// gestures. Kept pure so they can be unit tested without a widget tree.
class WordHit {
  final String word;
  final int start;
  final int end;

  const WordHit(this.word, this.start, this.end);
}

bool _isWordChar(String ch) {
  final code = ch.codeUnitAt(0);
  return (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      code == 39 ||
      code == 45;
}

bool _hasLetter(String value) {
  for (final code in value.codeUnits) {
    if ((code >= 65 && code <= 90) || (code >= 97 && code <= 122)) return true;
  }
  return false;
}

/// Word under [offset]. Taps that land just beside a word snap onto it, and
/// leading/trailing joiners are trimmed so `"word"` and `word-` yield `word`.
WordHit? wordAt(String text, int offset) {
  if (text.isEmpty) return null;
  var i = offset.clamp(0, text.length - 1);
  if (!_isWordChar(text[i])) {
    if (i > 0 && _isWordChar(text[i - 1])) {
      i -= 1;
    } else if (i + 1 < text.length && _isWordChar(text[i + 1])) {
      i += 1;
    } else {
      return null;
    }
  }
  var start = i;
  var end = i + 1;
  while (start > 0 && _isWordChar(text[start - 1])) {
    start -= 1;
  }
  while (end < text.length && _isWordChar(text[end])) {
    end += 1;
  }
  while (start < end && !_hasLetter(text[start])) {
    start += 1;
  }
  while (end > start && !_hasLetter(text[end - 1])) {
    end -= 1;
  }
  if (end <= start) return null;
  return WordHit(text.substring(start, end), start, end);
}

final _sentencePattern = RegExp(r'[^.!?]+[.!?]*');

/// Sentence that fully contains [start]..[end], falling back to the whole
/// paragraph when the range crosses sentence borders.
String sentenceAt(String text, int start, int end) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return '';
  for (final match in _sentencePattern.allMatches(text)) {
    if (start >= match.start && end <= match.end) {
      final sentence = match.group(0)?.trim() ?? '';
      if (sentence.isNotEmpty) return sentence;
    }
  }
  return trimmed;
}

/// Number of sentences in [text], used to report how much a selection covers.
int sentenceCount(String text) {
  var count = 0;
  for (final match in _sentencePattern.allMatches(text)) {
    final sentence = match.group(0)?.trim() ?? '';
    if (sentence.isNotEmpty) count += 1;
  }
  return count;
}
