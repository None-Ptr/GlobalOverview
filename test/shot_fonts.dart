import 'dart:io';

import 'package:flutter/services.dart';

/// 截图用例用的真实字体：Roboto 负责拉丁，微软雅黑补中文，
/// MaterialIcons 让底部导航和箭头出图标而不是方框。
Future<void> loadShotFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? 'D:/flutter';
  final roboto = Directory('$root/bin/cache/artifacts/material_fonts');
  if (roboto.existsSync()) {
    final loader = FontLoader('Roboto');
    for (final name in [
      'roboto-regular.ttf',
      'roboto-medium.ttf',
      'roboto-bold.ttf',
    ]) {
      final file = File('${roboto.path}/$name');
      if (!file.existsSync()) continue;
      loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await loader.load();

    final icons = File('${roboto.path}/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final iconLoader = FontLoader('MaterialIcons');
      iconLoader.addFont(
        Future.value(ByteData.sublistView(icons.readAsBytesSync())),
      );
      await iconLoader.load();
    }
  }

  // The reader draws article text in the bundled Literata; without it the
  // screenshot shows tofu boxes.
  final literata = File('assets/fonts/Literata-Regular.ttf');
  final literataSemi = File('assets/fonts/Literata-SemiBold.ttf');
  if (literata.existsSync()) {
    final loader = FontLoader('Literata');
    loader.addFont(
      Future.value(ByteData.sublistView(literata.readAsBytesSync())),
    );
    if (literataSemi.existsSync()) {
      loader.addFont(
        Future.value(ByteData.sublistView(literataSemi.readAsBytesSync())),
      );
    }
    await loader.load();
  }

  final cjk = File('C:/Windows/Fonts/msyh.ttc');
  if (cjk.existsSync()) {
    final bytes = cjk.readAsBytesSync();
    // 'Roboto' 也注册一份：TDesign 的内部按钮样式把家族钉死成 Roboto 且不带
    // fallback，测试环境没有系统兜底，不注册就会把中文画成方框。
    for (final family in [
      'CJK',
      'PingFang SC',
      'Microsoft YaHei',
      'Roboto',
    ]) {
      final loader = FontLoader(family);
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  }
}
