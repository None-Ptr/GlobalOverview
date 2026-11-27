import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// What actually happened, so the caller can say it plainly instead of a
/// blanket "已分享".
enum ShareOutcome { shared, dismissed, copied, failed }

/// One way to hand something out of the app: text to a chat, a file to
/// another app. The platform sheet does the work; the clipboard is the floor
/// when the device has no sheet at all (a desktop build without one).
class ShareService {
  const ShareService();

  Future<ShareOutcome> shareText({required String text, String? subject}) async {
    if (text.trim().isEmpty) return ShareOutcome.failed;
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          text: text,
          subject: subject,
          // A mail client is not a share sheet; the clipboard is a better
          // fallback than dragging the reader into a draft they did not want.
          mailToFallbackEnabled: false,
        ),
      );
      return result.status == ShareResultStatus.dismissed
          ? ShareOutcome.dismissed
          : ShareOutcome.shared;
    } catch (_) {
      try {
        await Clipboard.setData(ClipboardData(text: text));
        return ShareOutcome.copied;
      } catch (_) {
        return ShareOutcome.failed;
      }
    }
  }

  Future<ShareOutcome> shareFile({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? subject,
    String? text,
  }) async {
    if (bytes.isEmpty) return ShareOutcome.failed;
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes, mimeType: mimeType, name: fileName),
          ],
          fileNameOverrides: [fileName],
          subject: subject,
          text: text,
          // On the web this turns "no share sheet" into a download, which is
          // exactly what the reader wants from an export button there.
          downloadFallbackEnabled: true,
          mailToFallbackEnabled: false,
        ),
      );
      return result.status == ShareResultStatus.dismissed
          ? ShareOutcome.dismissed
          : ShareOutcome.shared;
    } catch (_) {
      return ShareOutcome.failed;
    }
  }
}
