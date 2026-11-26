import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The one file name the backup round-trip uses. Export writes it, import
/// reads it back, so the two never drift apart.
const String backupFileName = 'global_overview_learning.json';

/// Writes the backup into the app's documents directory and returns the path
/// so the caller can open it or share it.
Future<String?> saveBackupText(String content) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$backupFileName');
  await file.writeAsString(content);
  return file.path;
}

/// Reads the backup this app wrote, or null when there is none yet. Native has
/// no file picker here on purpose: the export already names the file, and
/// asking the reader to find it again is a worse trade than one known path.
Future<String?> readBackupText() async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$backupFileName');
  if (!await file.exists()) return null;
  return file.readAsString();
}
