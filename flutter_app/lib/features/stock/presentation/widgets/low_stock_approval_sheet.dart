import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/errors/user_facing_errors.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/providers/low_stock_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../../core/widgets/friendly_load_error.dart';

Future<void> showLowStockApprovalSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String itemId,
  required String itemName,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _LowStockApprovalSheetBody(
      parentRef: ref,
      itemId: itemId,
      itemName: itemName,
    ),
  );
}

class _LowStockApprovalSheetBody extends ConsumerStatefulWidget {
  const _LowStockApprovalSheetBody({
    required this.parentRef,
    required this.itemId,
    required this.itemName,
  });

  final WidgetRef parentRef;
  final String itemId;
  final String itemName;

  @override
  ConsumerState<_LowStockApprovalSheetBody> createState() =>
      _LowStockApprovalSheetBodyState();
}

class _LowStockApprovalSheetBodyState
    extends ConsumerState<_LowStockApprovalSheetBody> {
  late Future<({List<Map<String, dynamic>> lines, Map<String, dynamic> kpis})>
      _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<({List<Map<String, dynamic>> lines, Map<String, dynamic> kpis})> _load() async {
    final session = ref.read(sessionProvider);
    if (session == null) {
      return (
        lines: const <Map<String, dynamic>>[],
        kpis: const <String, dynamic>{},
      );
    }

    final businessId = session.primaryBusiness.id;
    final api = ref.read(hexaApiProvider);

    final lines = await api.listPendingStockAuditLinesForItem(
      businessId: businessId,
      itemId: widget.itemId,
    );
    final kpis = await api.getStockAuditKpis(businessId: businessId);

    return (lines: lines, kpis: kpis);
  }

  Future<void> _approveLine({
    required String lineId,
    required String auditId,
  }) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final businessId = session.primaryBusiness.id;

    await ref.read(hexaApiProvider).approveStockAuditLine(
          businessId: businessId,
          auditId: auditId,
          lineId: lineId,
        );

    // Update low-stock page counts immediately (owner view).
    ref.invalidate(lowStockOperationsSummaryProvider);
    ref.invalidate(lowStockOperationsPageProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return HexaResponsiveSheetViewport(
      child: FutureBuilder(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            return FriendlyLoadError(
              message: 'Could not load pending approvals',
              onRetry: () {
                if (!mounted) return;
                setState(() {
                  _future = _load();
                });
              },
            );
          }

          final data = snap.data;
          final lines = data?.lines ?? const <Map<String, dynamic>>[];
          final kpis = data?.kpis ?? const <String, dynamic>{};
          final pendingApprovalCount =
              coerceToInt(kpis['pending_approval_count']);

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Owner approval',
                        style: HexaDsType.heading(16,
                            color: HexaColors.textPrimary)
                            .copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  widget.itemName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(height: 10),
                if (pendingApprovalCount > 0)
                  Text(
                    '$pendingApprovalCount pending approvals overall',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                const SizedBox(height: 12),
                if (lines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'No pending approvals for this item right now.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: lines.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, thickness: 1),
                      itemBuilder: (ctx, idx) {
                        final ln = lines[idx];
                        final lineId = ln['id']?.toString() ?? '';
                        final auditId = ln['audit_id']?.toString() ?? '';
                        final auditDateRaw = ln['audit_date'];
                        final auditDate =
                            auditDateRaw is String ? DateTime.tryParse(auditDateRaw) : null;
                        final auditLabel = auditDate != null
                            ? '${auditDate.day} ${_monthLabel(auditDate.month)} ${auditDate.year}'
                            : 'Audit';

                        final systemQty = coerceToDouble(ln['system_qty']);
                        final countedQty = coerceToDouble(ln['counted_qty']);
                        final diffQty = coerceToDouble(ln['difference_qty']);
                        final reason = (ln['reason']?.toString() ?? '').trim();

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Audit: $auditLabel',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'System: ${systemQty.isFinite ? formatStockQtyNumber(systemQty) : '—'} • Counted: ${countedQty.isFinite ? formatStockQtyNumber(countedQty) : '—'}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Difference: ${diffQty.isFinite ? formatStockQtyNumber(diffQty.abs()) : '—'} ${diffQty.isFinite && diffQty < 0 ? '(system < counted)' : ''}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: HexaColors.loss,
                                ),
                              ),
                              if (reason.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Reason: $reason',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            HexaColors.brandPrimary,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed:
                                          lineId.isEmpty || auditId.isEmpty
                                              ? null
                                              : () async {
                                                  try {
                                                    await _approveLine(
                                                      lineId: lineId,
                                                      auditId: auditId,
                                                    );
                                                  } catch (e) {
                                                    if (!context.mounted) return;
                                                    ScaffoldMessenger.of(context)
                                                        .showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          userFacingError(e),
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                },
                                      child: const Text('Approve'),
                                    ),
                                  ),
                                ],
                              )
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _monthLabel(int m) {
    return switch (m) {
      1 => 'Jan',
      2 => 'Feb',
      3 => 'Mar',
      4 => 'Apr',
      5 => 'May',
      6 => 'Jun',
      7 => 'Jul',
      8 => 'Aug',
      9 => 'Sep',
      10 => 'Oct',
      11 => 'Nov',
      12 => 'Dec',
      _ => '',
    };
  }
}

