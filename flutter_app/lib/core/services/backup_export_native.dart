import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Saves export bytes under:
/// - Android/iOS: user-visible Downloads `HarisreeWarehouse/{year}/{month}/{category}/`
/// - Windows/macOS/Linux: Downloads `HarisreeWarehouse/{year}/{month}/{category}/`
/// - When [useDesktopFolder] on Windows: `Desktop/Harisree_Backups/{year}/{month}/{category}/`
///
/// Falls back to app documents directory when Downloads is unavailable.
Future<String?> saveBackupExportBytes({
  required Uint8List bytes,
  required String filename,
  required String category,
  bool useDesktopFolder = false,
}) async {
  try {
    final now = DateTime.now();
    final Directory root;
    if (useDesktopFolder && Platform.isWindows) {
      final profile = Platform.environment['USERPROFILE'];
      if (profile != null && profile.isNotEmpty) {
        root = Directory('$profile${Platform.pathSeparator}Desktop${Platform.pathSeparator}Harisree_Backups');
      } else {
        root = await _defaultExportRoot();
      }
    } else {
      root = await _defaultExportRoot();
    }
    final dirPath = [
      root.path,
      'HarisreeWarehouse',
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

Future<Directory> _defaultExportRoot() async {
  // Prefer user-visible Downloads directory on all platforms.
  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
  } catch (_) {
    // getDownloadsDirectory not available — fall through.
  }
  return getApplicationDocumentsDirectory();
}
