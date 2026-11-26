import 'dart:js_interop';

/// The browser's own speech engine. No endpoint, no CORS, no mp3 bytes: the
/// page hands text to SpeechSynthesis and the platform voice reads it.
@JS('speechSynthesis')
external _Synthesis get _synthesis;

extension type _Synthesis(JSObject _) implements JSObject {
  external void speak(_Utterance utterance);
  external void cancel();
  external bool get speaking;
}

@JS('SpeechSynthesisUtterance')
extension type _Utterance._(JSObject _) implements JSObject {
  external factory _Utterance(JSString text);
  external set lang(JSString value);
  external set rate(double value);
  external set pitch(double value);
}

bool get browserTtsAvailable => true;

void browserTtsSpeak(
  String text, {
  required String lang,
  required double rate,
  required double pitch,
}) {
  _synthesis.cancel();
  final utterance = _Utterance(text.toJS)
    ..lang = lang.toJS
    ..rate = rate
    ..pitch = pitch;
  _synthesis.speak(utterance);
}

bool get browserTtsSpeaking => _synthesis.speaking;

void browserTtsCancel() => _synthesis.cancel();
