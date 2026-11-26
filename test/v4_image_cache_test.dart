import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:global_overview/services/http_service.dart';
import 'package:global_overview/v4/services/image_cache.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('v4_images');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('下载一次后复用本地文件', () async {
    var calls = 0;
    final cache = V4ImageCache(
      HttpService(
        client: MockClient((request) async {
          calls++;
          return http.Response.bytes([1, 2, 3], 200);
        }),
      ),
      root: dir,
    );

    final first = await cache.resolve('https://example.com/a.png');
    final second = await cache.resolve('https://example.com/a.png');

    expect(first, isNotNull);
    expect(await first!.length(), 3);
    expect(second!.path, first.path);
    expect(calls, 1);
  });

  test('抓取失败返回 null，不留下文件', () async {
    final cache = V4ImageCache(
      HttpService(client: MockClient((request) async => http.Response('no', 404))),
      root: dir,
    );

    expect(await cache.resolve('https://example.com/missing.png'), isNull);
    expect(dir.listSync().whereType<File>().length, 0);
  });

  test('超过上限时淘汰最旧的文件', () async {
    for (var i = 0; i < V4ImageCache.maxFiles + 4; i++) {
      final file = File(dir.path + Platform.pathSeparator + 'seed' + i.toString());
      await file.writeAsBytes([0]);
      await file.setLastModified(
        DateTime.now().subtract(Duration(minutes: V4ImageCache.maxFiles + 8 - i)),
      );
    }
    final cache = V4ImageCache(
      HttpService(client: MockClient((request) async => http.Response.bytes([1], 200))),
      root: dir,
    );

    await cache.resolve('https://example.com/new.png');

    final files = dir.listSync().whereType<File>().toList();
    expect(files.length, V4ImageCache.maxFiles);
    expect(files.any((f) => f.path.endsWith('seed0')), isFalse);
  });

  test('clear 删掉全部缓存图片', () async {
    final cache = V4ImageCache(
      HttpService(client: MockClient((request) async => http.Response.bytes([1], 200))),
      root: dir,
    );
    await cache.resolve('https://example.com/a.png');
    await cache.resolve('https://example.com/b.png');

    await cache.clear();

    expect(dir.listSync().whereType<File>().length, 0);
  });
}
