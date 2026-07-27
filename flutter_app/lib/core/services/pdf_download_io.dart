import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

String _supplierFolderSlug(String filename) {
  // PO_SUPPLIER_25_MAY_2026.pdf → SUPPLIER segment
  final base = filename.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
  final parts = base.split('_');
  if (parts.length < 4 || parts.first.toUpperCase() != 'PO') {
    return 'exports';
  }
  final dateIdx = parts.lastIndexWhere((s) => RegExp(r'^\d{4}$').hasMatch(s));
  if (dateIdx <= 2) return parts.skip(1).join('_');
  return parts.sublist(1, dateIdx - 2).join('_');
}

/// Saves PDF under app documents:
/// `warehouse_exports/{year}/{month}/{supplier_slug}/{filename}`.
Future<bool> downloadPdfBytes(Uint8List bytes, String filename) async {
  try {
    final now = DateTime.now();
    final root = await getApplicationDocumentsDirectory();
    final supplier = _supplierFolderSlug(filename);
    final dirPath = [
      root.path,
      'warehouse_exports',
      now.year.toString(),
      now.month.toString().padLeft(2, '0'),
      supplier,
    ].join(Platform.pathSeparator);
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('$dirPath${Platform.pathSeparator}$filename');
    await file.writeAsBytes(bytes, flush: true);
    return true;
  } catch (_) {
    return false;
  }
}
