import 'dart:typed_data';

/// Non-web: Web Share API unavailable.
Future<bool> tryWebSharePurchasePdf({
  required Uint8List bytes,
  required String filename,
  required String text,
  required String title,
}) async =>
    false;
