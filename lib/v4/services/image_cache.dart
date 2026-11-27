import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:global_overview/services/http_service.dart';
import 'package:path_provider/path_provider.dart';

/// Article images on disk: one file per URL, newest [maxFiles] kept.
///
/// A feed reader reopens the same article many times; re-downloading every
/// figure over mobile data is the one thing a reader must not do.
class V4ImageCache {
  V4ImageCache(this._http, {Directory? root}) : _root = root;

  static const maxFiles = 120;
  static const maxBytes = 6 * 1024 * 1024;

  final HttpService _http;
  Directory? _root;
  final _pending = <String, Future<File?>>{};

  Future<File?> resolve(String url) async {
    // The browser loads figures through <img>, which needs no CORS header and
    // no disk cache; there is also no file system to write them to.
    if (kIsWeb || url.isEmpty) return null;
    return _pending.putIfAbsent(url, () => _resolve(url));
  }

  Future<File?> _resolve(String url) async {
    try {
      final dir = await _dir();
      if (dir == null) return null;
      final file = File(dir.path + Platform.pathSeparator + _key(url));
      if (await file.exists() && await file.length() > 0) return file;
      final bytes = await _http.getBytes(url);
      if (bytes.length > maxBytes) return null;
      await file.writeAsBytes(bytes, flush: true);
      await _prune(dir);
      return file;
    } catch (_) {
      return null;
    } finally {
      _pending.remove(url);
    }
  }

  Future<void> clear() async {
    if (kIsWeb) return;
    final dir = await _dir();
    if (dir == null) return;
    try {
      await for (final entry in dir.list()) {
        if (entry is File) await entry.delete();
      }
    } catch (_) {}
  }

  Future<Directory?> _dir() async {
    final cached = _root;
    if (cached != null) return cached;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(base.path + Platform.pathSeparator + 'images');
      if (!await dir.exists()) await dir.create(recursive: true);
      return _root = dir;
    } catch (_) {
      return null;
    }
  }

  String _key(String url) => sha1.convert(url.codeUnits).toString();

  Future<void> _prune(Directory dir) async {
    final files = <File>[];
    await for (final entry in dir.list()) {
      if (entry is File) files.add(entry);
    }
    if (files.length <= maxFiles) return;
    final stamped = <({File file, DateTime at})>[];
    for (final file in files) {
      try {
        stamped.add((file: file, at: await file.lastModified()));
      } catch (_) {}
    }
    stamped.sort((a, b) => a.at.compareTo(b.at));
    final drop = stamped.length - maxFiles;
    for (var i = 0; i < drop; i++) {
      try {
        await stamped[i].file.delete();
      } catch (_) {}
    }
  }
}