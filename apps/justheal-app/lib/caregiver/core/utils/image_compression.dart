import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// The result of [compressImageIfPossible] — bytes plus a filename with the
/// extension corrected to match, since a caller (upload code) derives the
/// HTTP content-type it sends from the filename extension, not by
/// inspecting the bytes.
class CompressedFile {
  final Uint8List bytes;
  final String filename;

  const CompressedFile(this.bytes, this.filename);
}

/// Best-effort client-side compression for a document picked via
/// FilePicker (Aadhaar/qualification/other) — unlike the selfie's
/// ImagePicker.pickImage call, FilePicker has no native resize/quality
/// option of its own, so a raw camera photo or phone-gallery image can
/// land here completely uncompressed (seen in production: 1-2MB files for
/// a document that only needs to be legible, not print-quality).
///
/// Recognizes only image-type filenames by extension — CLAUDE.md forbids
/// validating/rejecting uploads by MIME type, so this never blocks or
/// rejects a non-image upload (e.g. a PDF), it just leaves it untouched.
/// Runs the actual decode/resize/encode on a background isolate via
/// [compute], since that work is CPU-heavy enough to jank the UI thread
/// for a full-resolution photo. Falls back to the original bytes/filename
/// on any decode failure (e.g. HEIC, which the pure-Dart decoder can't
/// read) or if compression didn't actually shrink the file.
Future<CompressedFile> compressImageIfPossible(Uint8List bytes, String filename) async {
  if (!_looksLikeImage(filename)) return CompressedFile(bytes, filename);
  try {
    final compressed = await compute(_compress, bytes);
    if (compressed == null || compressed.length >= bytes.length) {
      return CompressedFile(bytes, filename);
    }
    return CompressedFile(compressed, _withJpgExtension(filename));
  } catch (_) {
    return CompressedFile(bytes, filename);
  }
}

bool _looksLikeImage(String filename) {
  final lower = filename.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.bmp');
}

String _withJpgExtension(String filename) {
  final dotIndex = filename.lastIndexOf('.');
  final base = dotIndex == -1 ? filename : filename.substring(0, dotIndex);
  return '$base.jpg';
}

/// The longest edge a document upload is downscaled to — generous enough
/// that text on an ID document stays legible, far more than the app itself
/// ever displays a document at.
const _maxDimension = 1600;

/// Top-level (not a closure) so it can run via [compute] on a background
/// isolate.
Uint8List? _compress(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  final needsResize = decoded.width > _maxDimension || decoded.height > _maxDimension;
  final resized = !needsResize
      ? decoded
      : img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? _maxDimension : null,
          height: decoded.height > decoded.width ? _maxDimension : null,
        );

  return img.encodeJpg(resized, quality: 85);
}
