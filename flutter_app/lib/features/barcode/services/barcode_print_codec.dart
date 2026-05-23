import 'barcode_pdf_service.dart';

/// Normalizes text for Code128 (ASCII printable only).
String sanitizeCode128Payload(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '0';
  final buf = StringBuffer();
  for (final unit in trimmed.codeUnits) {
    if (unit >= 32 && unit <= 126) {
      buf.writeCharCode(unit);
    }
  }
  var out = buf.toString();
  if (out.isEmpty) out = '0';
  if (out.length > 48) out = out.substring(0, 48);
  return out;
}

/// QR tolerates more characters; keep length bounded for web PDF performance.
String sanitizeQrPayload(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '0';
  if (s.length > 120) s = s.substring(0, 120);
  return s;
}

String sanitizeSymbology(String raw, {required bool forQr}) =>
    forQr ? sanitizeQrPayload(raw) : sanitizeCode128Payload(raw);

/// Remove duplicate labels (API + stock fallback can double-count).
List<BarcodeLabelData> dedupeBarcodeLabels(List<BarcodeLabelData> items) {
  final seen = <String>{};
  final out = <BarcodeLabelData>[];
  for (final l in items) {
    final key =
        '${l.itemCode.trim().toLowerCase()}|${(l.barcode ?? '').trim().toLowerCase()}';
    if (seen.add(key)) out.add(l);
  }
  return out;
}
