import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Saves export bytes under app documents:
/// `warehouse_exports/{year}/{month}/{category}/{filename}`.
Future<String?> saveBackupExportBytes({
  required Uint8List bytes,
  required String filename,
  required String category,
}) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return null;
  }
  try {
    final now = DateTime.now();
    final root = await getApplicationDocumentsDirectory();
    final dirPath = [
      root.path,
      'warehouse_exports',
      now.year.toString(),
      now.month.toString().padLeft(2, '0'),
      category,
    ].join(Platform.pathSeparator);
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('$dirPath${Platform.pathSeparator}$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}
