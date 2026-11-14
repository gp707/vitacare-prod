import 'dart:typed_data';

/// Where there is no browser (unit tests), there is nothing to save to.
Future<void> downloadFile(String fileName, Uint8List bytes, String mimeType) async {}
