import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/providers/purchase_damage_reports_provider.dart';

class PurchaseDetailDamageSection extends ConsumerStatefulWidget {
  const PurchaseDetailDamageSection({
    super.key,
    required this.purchaseId,
    this.canReport = false,
    this.onReport,
    this.canManageStatus = false,
  });

  final String purchaseId;
  final bool canReport;
  final VoidCallback? onReport;
  final bool canManageStatus;

  @override
  ConsumerState<PurchaseDetailDamageSection> createState() =>
      _PurchaseDetailDamageSectionState();
}

class _PurchaseDetailDamageSectionState
    extends ConsumerState<PurchaseDetailDamageSection> {
  bool _expanded = false;
  String? _busyReportId;

  Future<void> _patchStatus(String reportId, String status) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() => _busyReportId = reportId);
    try {
      await ref.read(hexaApiProvider).patchPurchaseDamageReportStatus(
            businessId: session.primaryBusiness.id,
            reportId: reportId,
            status: status,
          );
      ref.invalidate(purchaseDamageReportsProvider(widget.purchaseId));
      ref.invalidate(pendingDamageReportsCountProvider);
    } finally {
      if (mounted) setState(() => _busyReportId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reportsAsync =
        ref.watch(purchaseDamageReportsProvider(widget.purchaseId));
    final count = reportsAsync.valueOrNull?.length ?? 0;
    final pending = reportsAsync.valueOrNull
            ?.where((r) => (r['status']?.toString() ?? 'pending') == 'pending')
            .length ??
        0;

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: _expanded,
        onExpansionChanged: (v) => setState(() => _expanded = v),
        title: Text(
          'Damage / returns${count > 0 ? ' ($count)' : ''}${pending > 0 ? ' · $pending pending' : ''}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        children: [
          if (widget.canReport && widget.onReport != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: widget.onReport,
                  icon: const Icon(Icons.report_outlined, size: 18),
                  label: const Text('Report damage'),
                ),
              ),
            ),
          ],
          reportsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
            error: (_, __) => const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Could not load damage reports'),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    'No damage or short-delivery reports for this purchase.',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                );
              }
              return Column(
                children: [
                  for (final r in rows)
                    _DamageReportRow(
                      report: r,
                      canManage: widget.canManageStatus,
                      busy: _busyReportId == r['id']?.toString(),
                      onPatch: _patchStatus,
                    ),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DamageReportRow extends StatelessWidget {
  const _DamageReportRow({
    required this.report,
    required this.canManage,
    required this.busy,
    required this.onPatch,
  });

  final Map<String, dynamic> report;
  final bool canManage;
  final bool busy;
  final void Function(String reportId, String status) onPatch;

  static String _typeLabel(String t) {
    switch (t) {
      case 'short':
        return 'Short';
      case 'missing':
        return 'Missing';
      case 'returned':
        return 'Returned';
      default:
        return 'Damaged';
    }
  }

  static String _reasonLabel(String? r) {
    switch (r) {
      case 'torn_bag':
        return 'Torn bag';
      case 'wet_damage':
        return 'Wet damage';
      case 'wrong_item':
        return 'Wrong item';
      case 'short_weight':
        return 'Short weight';
      case 'other':
        return 'Other';
      default:
        return '';
    }
  }

  static String _statusLabel(String s) {
    switch (s) {
      case 'approved':
        return 'Approved';
      case 'returned':
        return 'Returned';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = report['damage_type']?.toString() ?? 'damaged';
    final reason = _reasonLabel(report['reason']?.toString());
    final item = report['item_name']?.toString() ?? 'Item';
    final qty = report['qty_damaged'];
    final unit = report['unit']?.toString();
    final status = report['status']?.toString() ?? 'pending';
    final by = report['reported_by']?.toString();
    final id = report['id']?.toString() ?? '';
    DateTime? at;
    try {
      at = DateTime.parse(report['created_at']?.toString() ?? '');
    } catch (_) {}

    return ListTile(
      dense: true,
      leading: Chip(
        label: Text(
          _statusLabel(status),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
      ),
      title: Text(item, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              _typeLabel(type),
              if (reason.isNotEmpty) reason,
              if (qty != null) 'Qty $qty${unit != null && unit.isNotEmpty ? ' $unit' : ''}',
              if (by != null && by.isNotEmpty) 'By $by',
              if (at != null) DateFormat('d MMM, h:mm a').format(at.toLocal()),
            ].join(' · '),
          ),
          if (canManage && status == 'pending' && id.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                ActionChip(
                  label: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Approve'),
                  onPressed: busy ? null : () => onPatch(id, 'approved'),
                ),
                ActionChip(
                  label: const Text('Return'),
                  onPressed: busy ? null : () => onPatch(id, 'returned'),
                ),
                ActionChip(
                  label: const Text('Reject'),
                  onPressed: busy ? null : () => onPatch(id, 'rejected'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
