import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:caregiver_app/core/utils/image_compression.dart';

/// Genuinely high-entropy per-pixel noise (not a smooth/periodic pattern,
/// which PNG's filters would compress away almost entirely) — a much
/// closer stand-in for a real camera photo/document scan, where JPEG
/// re-encoding at a smaller resolution actually has something to win
/// against.
Uint8List _pngOf(int width, int height, {int seed = 1}) {
  final random = Random(seed);
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, random.nextInt(256), random.nextInt(256), random.nextInt(256));
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('compressImageIfPossible', () {
    test('shrinks a large image and renames it to .jpg', () async {
      final original = _pngOf(2400, 1800);
      final result = await compressImageIfPossible(original, 'aadhaar.png');

      expect(result.bytes.length, lessThan(original.length));
      expect(result.filename, 'aadhaar.jpg');

      final decoded = img.decodeImage(result.bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(1600));
      expect(decoded.height, lessThanOrEqualTo(1600));
    });

    test('preserves aspect ratio when downscaling a portrait image', () async {
      final original = _pngOf(1200, 2400);
      final result = await compressImageIfPossible(original, 'doc.png');
      final decoded = img.decodeImage(result.bytes)!;

      expect(decoded.height, 1600);
      expect(decoded.width, 800);
    });

    test('leaves a non-image file (by extension) completely untouched', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final result = await compressImageIfPossible(bytes, 'resume.pdf');

      expect(result.bytes, same(bytes));
      expect(result.filename, 'resume.pdf');
    });

    test('falls back to the original bytes when decoding fails', () async {
      final bytes = Uint8List.fromList([0xff, 0xd8, 0x00, 0x01, 0x02]);
      final result = await compressImageIfPossible(bytes, 'broken.jpg');

      expect(result.bytes, same(bytes));
      expect(result.filename, 'broken.jpg');
    });

    test('does not upscale or otherwise expand an already-small image', () async {
      final original = _pngOf(200, 150);
      final result = await compressImageIfPossible(original, 'small.png');

      // Either the original wins outright (compression didn't help a tiny
      // image), or a same/smaller JPEG re-encode is kept — never larger,
      // and never resized up.
      expect(result.bytes.length, lessThanOrEqualTo(original.length));
      final decoded = img.decodeImage(result.bytes)!;
      expect(decoded.width, 200);
      expect(decoded.height, 150);
    });
  });
}
