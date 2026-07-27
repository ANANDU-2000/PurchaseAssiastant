import 'package:flutter/material.dart';

/// Warehouse stock row status pill (OK / LOW / OUT / NO CODE / RECENT).
enum StockRowStatusKind {
  ok,
  low,
  out,
  missingBarcode,
  recent,
}

class StockStatusBadge extends StatelessWidget {
  const StockStatusBadge({
    super.key,
    required this.kind,
    this.compact = true,
  });

  final StockRowStatusKind kind;
  final bool compact;

  static StockRowStatusKind resolve({
    required String stockStatus,
    required bool missingBarcode,
    String? updatedAtIso,
  }) {
    final st = stockStatus.toLowerCase();
    if (st == 'out') return StockRowStatusKind.out;
    if (st == 'low' || st == 'critical') return StockRowStatusKind.low;
    if (missingBarcode) return StockRowStatusKind.missingBarcode;
    if (_isRecentlyUpdated(updatedAtIso)) return StockRowStatusKind.recent;
    return StockRowStatusKind.ok;
  }

  static bool _isRecentlyUpdated(String? iso) {
    if (iso == null || iso.isEmpty) return false;
    final dt = DateTime.tryParse(iso);
    if (dt == null) return false;
    return DateTime.now().difference(dt.toLocal()) < const Duration(minutes: 15);
  }

  (String label, Color fg, Color bg) get _style => switch (kind) {
        StockRowStatusKind.ok => (
            'OK',
            Colors.white,
            const Color(0xFF16A34A),
          ),
        StockRowStatusKind.low => (
            'LOW',
            Colors.white,
            const Color(0xFFDC2626),
          ),
        StockRowStatusKind.out => (
            'OUT',
            const Color(0xFF6B7280),
            const Color(0xFFE5E7EB),
          ),
        StockRowStatusKind.missingBarcode => (
            'NO CODE',
            Colors.white,
            const Color(0xFF6A1B9A),
          ),
        StockRowStatusKind.recent => (
            'RECENT',
            Colors.white,
            const Color(0xFF1565C0),
          ),
      };

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = _style;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w800,
          color: fg,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

String formatStockRelativeTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt.toLocal());
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${dt.day}/${dt.month}';
}
