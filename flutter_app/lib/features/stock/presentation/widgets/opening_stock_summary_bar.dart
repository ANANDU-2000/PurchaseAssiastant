import 'package:flutter/material.dart';

import 'stock_status_badge.dart';

/// Compact operational summary bar for Opening Stock Setup.
class OpeningStockSummaryBar extends StatelessWidget {
  const OpeningStockSummaryBar({
    super.key,
    required this.pendingCount,
    required this.completedCount,
    required this.totalCount,
    this.lastUpdatedAtIso,
    this.lastUpdatedBy,
  });

  final int pendingCount;
  final int completedCount;
  final int totalCount;
  final String? lastUpdatedAtIso;
  final String? lastUpdatedBy;

  @override
  Widget build(BuildContext context) {
    final remaining = totalCount - completedCount;
    final rel = formatStockRelativeTime(lastUpdatedAtIso);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          border: Border.all(color: const Color(0xFFD8D5D0)),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '━━━━━━━━━━━━━━━━━━━',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$pendingCount Pending',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFE65100),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '$completedCount Completed',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF16A34A),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text(
                    '$remaining Remaining',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (lastUpdatedBy != null &&
                lastUpdatedBy!.trim().isNotEmpty &&
                (lastUpdatedAtIso == null || lastUpdatedAtIso!.isEmpty || rel
                    .trim()
                    .isEmpty)) ...[
              Text(
                'Last updated by $lastUpdatedBy',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
            if (lastUpdatedBy != null &&
                lastUpdatedBy!.trim().isNotEmpty &&
                rel.trim().isNotEmpty) ...[
              Text(
                'Last: $lastUpdatedBy${rel.isNotEmpty ? ' · $rel' : ''}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

