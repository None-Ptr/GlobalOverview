import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 朗读：系统原生 TTS（flutter_tts），无需接口配置。
class TtsService {
  final FlutterTts _tts = FlutterTts();

  /// 播放状态（true=正在朗读）。UI 应监听它，而不是自己猜。
  final ValueNotifier<bool> playing = ValueNotifier<bool>(false);

  static const _timeout = Duration(seconds: 4);

  TtsService() {
    _tts.awaitSpeakCompletion(false);
    _tts.setLanguage('en-US');
    _tts.setPitch(1.0);
    _tts.setVolume(1.0);
    _tts.setSpeechRate(0.5);
    _tts.setCompletionHandler(() => playing.value = false);
    _tts.setCancelHandler(() => playing.value = false);
    _tts.setErrorHandler((_) => playing.value = false);
  }

  bool get isPlaying => playing.value;

  Future<void> stop() async {
    playing.value = false;
    try {
      await _tts.stop().timeout(_timeout);
    } catch (_) {}
  }

  /// 立即返回（不等待朗读结束）；完成/取消/出错由回调维护 [playing]。
  Future<void> speak(String text, {double rate = 0.5}) async {
    final input = text.trim();
    if (input.isEmpty) throw Exception('没有可朗读的文本');
    try {
      await _tts.stop().timeout(_timeout);
    } catch (_) {}
    try {
      await _tts.setSpeechRate(rate).timeout(_timeout);
    } catch (_) {}
    playing.value = true;
    unawaited(_tts.speak(input).catchError((_) {
      playing.value = false;
      return 0;
    }));
  }
}
