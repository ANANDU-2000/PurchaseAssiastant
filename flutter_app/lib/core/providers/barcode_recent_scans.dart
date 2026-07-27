import 'dart:convert';

import '../../core/services/prefs_helper.dart';

/// Shared with [BarcodeScanPage] and staff home — keep in sync.
const kBarcodeRecentScansPrefsKey = 'barcode_recent_scans_v1';

/// One successful barcode lookup stored for recent-scan chips.
class BarcodeRecentScan {
  const BarcodeRecentScan({
    required this.id,
    required this.name,
    required this.code,
  });

  final String id;
  final String name;
  final String code;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
      };

  factory BarcodeRecentScan.fromJson(Map<String, dynamic> j) {
    return BarcodeRecentScan(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      code: j['code']?.toString() ?? '',
    );
  }

  /// Legacy prefs stored plain item codes only.
  factory BarcodeRecentScan.legacyCode(String code) =>
      BarcodeRecentScan(id: '', name: code, code: code);
}

Future<List<BarcodeRecentScan>> loadBarcodeRecentScans({int max = 10}) async {
  final p = PrefsHelper.prefs;
  final raw = p.getString(kBarcodeRecentScansPrefsKey);
  if (raw == null || raw.isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    final out = <BarcodeRecentScan>[];
    for (final e in decoded) {
      if (e is Map) {
        final row = BarcodeRecentScan.fromJson(Map<String, dynamic>.from(e));
        if (row.code.isNotEmpty) out.add(row);
      } else {
        final code = '$e'.trim();
        if (code.isNotEmpty) out.add(BarcodeRecentScan.legacyCode(code));
      }
    }
    return out.take(max).toList();
  } catch (_) {
    return [];
  }
}

Future<void> saveBarcodeRecentScans(List<BarcodeRecentScan> rows) async {
  final p = PrefsHelper.prefs;
  final payload = rows.map((e) => e.toJson()).toList();
  await p.setString(kBarcodeRecentScansPrefsKey, jsonEncode(payload));
}
