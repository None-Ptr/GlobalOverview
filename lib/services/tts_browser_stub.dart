/// Non-web stub. On Android and desktop the synthesizer is not available;
/// TtsService keeps using the Edge endpoint there.
bool get browserTtsAvailable => false;

void browserTtsSpeak(
  String text, {
  required String lang,
  required double rate,
  required double pitch,
}) {}

bool get browserTtsSpeaking => false;

void browserTtsCancel() {}
