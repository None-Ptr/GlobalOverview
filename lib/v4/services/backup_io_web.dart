import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// The one file name the backup round-trip uses. Export writes it, import
/// reads it back, so the two never drift apart.
const String backupFileName = 'global_overview_learning.json';

/// Downloads the backup. There is no documents directory to write into on the
/// web, so the browser's download is the save, and the return is null.
Future<String?> saveBackupText(String content) async {
  final bytes = Uint8List.fromList(utf8.encode(content));
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = backupFileName
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return null;
}

/// Opens the browser's file picker and returns the chosen file's text.
Future<String?> readBackupText() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.json,application/json';
  final completer = Completer<String?>();

  input.onchange = ((web.Event _) async {
    final files = input.files;
    final file = files == null || files.length == 0 ? null : files.item(0);
    if (file == null) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    try {
      final text = await file.text().toDart;
      if (!completer.isCompleted) completer.complete(text.toDart);
    } catch (_) {
      if (!completer.isCompleted) completer.complete(null);
    }
  }).toJS;

  input.click();
  return completer.future;
}
