import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'package:global_overview/services/app_config_service.dart';
import 'package:global_overview/services/http_service.dart';

import 'tts_browser_stub.dart' if (dart.library.html) 'tts_browser.dart';

/// 朗读：调用 LibreTTS 的 Edge 接口（/api/tts）合成 mp3，再用 audioplayers 播放。
/// 长文按句子切成多段依次播放，避免单次请求超过接口上限。
class TtsService {
  static const endpoint = 'https://edge.text-to-speech.cn/api/tts';
  static const _maxChars = 1800;

  final HttpService _http;
  final AppConfigService _config;
  final AudioPlayer _player = AudioPlayer();

  /// 播放状态（true=正在朗读）。UI 应监听它，而不是自己猜。
  final ValueNotifier<bool> playing = ValueNotifier<bool>(false);

  int _generation = 0;
  Completer<void>? _cancel;

  TtsService(this._http, this._config) {
    _player.setReleaseMode(ReleaseMode.stop);
  }

  bool get isPlaying => playing.value;

  Future<void> stop() async {
    _generation++;
    _cancel?.complete();
    _cancel = null;
    playing.value = false;
    try {
      browserTtsCancel();
      await _player.stop();
    } catch (_) {}
  }

  /// 合成并开始播放；首段合成失败会抛出，后续段落失败则静默结束。
  Future<void> speak(String text) async {
    final input = text.trim();
    if (input.isEmpty) throw Exception('没有可朗读的文本');
    await stop();
    final run = _generation;
    final cancel = Completer<void>();
    _cancel = cancel;
    playing.value = true;
    final chunks = _chunk(input);
    if (browserTtsAvailable) {
      unawaited(_speakBrowser(chunks, run, cancel));
      return;
    }
    try {
      final first = await _synthesize(chunks.first);
      if (run != _generation) return;
      unawaited(_playFrom(chunks, 0, first, run, cancel));
    } catch (_) {
      // [playing] was set before synthesis; a failed first chunk must not
      // leave the UI stuck on "stop speaking".
      if (run == _generation) {
        playing.value = false;
        _cancel = null;
      }
      rethrow;
    }
  }

  /// On the web the browser's own voice reads the text. Chunks are spoken one
  /// at a time so a long article cannot be cut short by a single utterance;
  /// the speaking flag keeps [playing] and the stop button in sync.
  Future<void> _speakBrowser(
    List<String> chunks,
    int run,
    Completer<void> cancel,
  ) async {
    try {
      final lang = _config.ttsVoice.split('-').take(2).join('-');
      final rate = (1 + _config.ttsRate * 0.1).clamp(0.5, 2.0).toDouble();
      final pitch = (1 + _config.ttsPitch * 0.1).clamp(0.5, 2.0).toDouble();
      for (final chunk in chunks) {
        if (run != _generation || cancel.isCompleted) return;
        browserTtsSpeak(chunk, lang: lang, rate: rate, pitch: pitch);
        await Future<void>.delayed(const Duration(milliseconds: 120));
        while (browserTtsSpeaking && run == _generation) {
          if (cancel.isCompleted) break;
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
        if (run != _generation || cancel.isCompleted) return;
      }
      // No cancel here: the last utterance has already ended, and calling
      // cancel can cut it off when speaking briefly reports false mid-queue.
      if (run == _generation) playing.value = false;
    } catch (_) {
      if (run == _generation) {
        playing.value = false;
        _cancel = null;
      }
    }
  }

  Future<void> _playFrom(
    List<String> chunks,
    int index,
    Uint8List bytes,
    int run,
    Completer<void> cancel,
  ) async {
    while (index < chunks.length && run == _generation) {
      Future<Uint8List>? next;
      if (index + 1 < chunks.length) {
        next = _synthesize(chunks[index + 1]);
      }
      try {
        await _play(bytes, cancel);
      } catch (_) {
        break;
      }
      if (run != _generation) return;
      if (next == null) break;
      try {
        bytes = await next;
      } catch (_) {
        break;
      }
      index++;
    }
    if (run == _generation) playing.value = false;
  }

  Future<void> _play(Uint8List bytes, Completer<void> cancel) async {
    await _player.stop();
    await _player.setSource(BytesSource(bytes, mimeType: 'audio/mpeg'));
    final done = Completer<void>();
    final sub = _player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.completed && !done.isCompleted) done.complete();
    });
    try {
      await _player.resume();
      await Future.any([done.future, cancel.future]);
    } finally {
      await sub.cancel();
    }
  }

  Future<Uint8List> _synthesize(String text) {
    return _http.postBytes(
      endpoint,
      {
        'text': text,
        'voice': _config.ttsVoice,
        'rate': _config.ttsRate,
        'pitch': _config.ttsPitch,
        'format': 'mp3',
      },
      headers: {'Accept': 'audio/mpeg'},
    );
  }

  List<String> _chunk(String text) {
    if (text.length <= _maxChars) return [text];
    final out = <String>[];
    var start = 0;
    while (start < text.length) {
      var end = start + _maxChars;
      if (end >= text.length) {
        final part = text.substring(start).trim();
        if (part.isNotEmpty) out.add(part);
        break;
      }
      final slice = text.substring(start, end);
      final cut = slice.lastIndexOf(RegExp(r'[.!?。！？]\s'));
      if (cut > _maxChars ~/ 2) end = start + cut + 1;
      final part = text.substring(start, end).trim();
      if (part.isNotEmpty) out.add(part);
      start = end;
    }
    return out.isEmpty ? [text] : out;
  }
}
