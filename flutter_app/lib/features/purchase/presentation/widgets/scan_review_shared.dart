import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';

/// Trader-friendly confidence band (no numeric % in UI).
Widget scanReviewConfidencePill(double c) {
  final (bg, fg, label) = c >= 0.85
      ? (const Color(0xFFECFDF5), const Color(0xFF065F46), 'HIGH')
      : (c >= 0.55
          ? (const Color(0xFFFFFBEB), const Color(0xFF92400E), 'MEDIUM')
          : (const Color(0xFFFEF2F2), const Color(0xFF991B1B), 'LOW'));
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: fg.withAlpha(35)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
    ),
  );
}

/// Same card as [ScanPurchaseV2Page] review header — keep one source for panel + v2.
Widget scanReviewConfidenceSummaryCard({
  required BuildContext context,
  required double overall,
  required bool needsReview,
  double? ocrExtractConfidence,
  bool hasTotalMismatch = false,
}) {
  return Card(
    margin: const EdgeInsets.only(top: 12),
    color: needsReview ? const Color(0xFFFFFBF5) : const Color(0xFFF8FAFC),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Scan confidence',
                  style: HexaDsType.formSectionLabel,
                ),
              ),
              scanReviewConfidencePill(overall),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: needsReview ? const Color(0xFFFFFBEB) : const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: needsReview ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                  ),
                ),
                child: Text(
                  needsReview ? 'Review' : 'OK',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: needsReview ? const Color(0xFF92400E) : const Color(0xFF065F46),
                  ),
                ),
              ),
            ],
          ),
          if (ocrExtractConfidence != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.text_fields_rounded, size: 16, color: Colors.black45),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Text read quality (OCR fallback)',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.black54,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                scanReviewConfidencePill(ocrExtractConfidence),
              ],
            ),
          ],
          if (hasTotalMismatch) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.compare_arrows_rounded, size: 18, color: Color(0xFFB45309)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Line totals do not match the bill total — check rates, units, and kg before continuing.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF92400E),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

Widget scanReviewMatchStateChip(Object? stateRaw) {
  final st = (stateRaw ?? 'unresolved').toString().trim().toLowerCase();
  final (bg, fg, label) = switch (st) {
    'auto' => (const Color(0xFFECFDF5), const Color(0xFF065F46), 'AUTO'),
    'needs_confirmation' => (const Color(0xFFFFFBEB), const Color(0xFF92400E), 'CONFIRM'),
    _ => (const Color(0xFFF3F4F6), const Color(0xFF374151), 'UNRESOLVED'),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: fg.withAlpha(40)),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w900,
        color: fg,
        letterSpacing: 0.3,
      ),
    ),
  );
}

/// Legacy [/scan-purchase] returns string parse_warnings only — show with severity heuristics.
Widget scanReviewLegacyWarningsList(BuildContext context, List<String> warnings) {
  if (warnings.isEmpty) return const SizedBox.shrink();
  final sorted = List<String>.from(warnings)..sort();
  return Card(
    margin: const EdgeInsets.only(top: 8),
    color: const Color(0xFFFFFBF5),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Scanner warnings',
            style: HexaDsType.formSectionLabel,
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < sorted.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _legacyWarningIcon(sorted[i]),
                  size: 18,
                  color: _legacyWarningColor(sorted[i]),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sorted[i],
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1F2937),
                        ),
                  ),
                ),
              ],
            ),
            if (i < sorted.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    ),
  );
}

IconData _legacyWarningIcon(String w) {
  final u = w.toUpperCase();
  if (u.contains('TOTAL_MISMATCH') ||
      u.contains('BLOCKER') ||
      u.contains('MUST') ||
      u.contains('INVALID')) {
    return Icons.error_outline_rounded;
  }
  if (u.contains('WARN') || u.contains('MISMATCH') || u.contains('UNCERTAIN')) {
    return Icons.warning_amber_rounded;
  }
  return Icons.info_outline_rounded;
}

Color _legacyWarningColor(String w) {
  final u = w.toUpperCase();
  if (u.contains('TOTAL_MISMATCH') ||
      u.contains('BLOCKER') ||
      u.contains('MUST') ||
      u.contains('INVALID')) {
    return const Color(0xFFB91C1C);
  }
  if (u.contains('WARN') || u.contains('MISMATCH') || u.contains('UNCERTAIN')) {
    return const Color(0xFFD97706);
  }
  return Colors.black45;
}
