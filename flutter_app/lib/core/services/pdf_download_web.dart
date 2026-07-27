import 'dart:typed_data';

import 'file_download_web.dart';

Future<bool> downloadPdfBytes(Uint8List bytes, String filename) async {
  return triggerBrowserFileDownload(bytes, filename, 'application/pdf');
}
