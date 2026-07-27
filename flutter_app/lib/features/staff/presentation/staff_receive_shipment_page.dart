import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import 'package:dio/dio.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/business_aggregates_invalidation.dart'
    show invalidateStaffDeliverySurfaces, syncPurchaseStockAfterVerify;
import '../../../core/providers/api_degraded_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/delivery_offline_actions.dart';
import '../../../core/utils/delivery_write_resilience.dart';
import '../../../core/utils/snack.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../purchase/providers/trade_purchase_detail_provider.dart';

class StaffReceiveShipmentPage extends ConsumerStatefulWidget {
  const StaffReceiveShipmentPage({super.key, required this.purchaseId});

  final String purchaseId;

  @override
  ConsumerState<StaffReceiveShipmentPage> createState() =>
      _StaffReceiveShipmentPageState();
}

class _StaffReceiveShipmentPageState
    extends ConsumerState<StaffReceiveShipmentPage> {
  final _notesCtrl = TextEditingController();
  final _truckCtrl = TextEditingController();
  final _driverCtrl = TextEditingController();
  final _receivedQty = <String, TextEditingController>{};
  final _damagedQty = <String, TextEditingController>{};
  String? _lineControllersPurchaseId;
  bool _saving = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    _truckCtrl.dispose();
    _driverCtrl.dispose();
    for (final c in _receivedQty.values) {
      c.dispose();
    }
    for (final c in _damagedQty.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _ensureLineControllers(TradePurchase p) {
    if (_lineControllersPurchaseId == p.id) return;
    for (final c in _receivedQty.values) {
      c.dispose();
    }
    for (final c in _damagedQty.values) {
      c.dispose();
    }
    _receivedQty.clear();
    _damagedQty.clear();
    for (final line in p.lines) {
      if (line.id.isEmpty) continue;
      _receivedQty[line.id] = TextEditingController(
        text: line.qty > 0 ? line.qty.toStringAsFixed(0) : '',
      );
      _damagedQty[line.id] = TextEditingController(text: '0');
    }
    _lineControllersPurchaseId = p.id;
  }

  double? _parseQty(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  List<Map<String, dynamic>>? _buildVerifyPayload(TradePurchase p) {
    final payload = <Map<String, dynamic>>[];
    for (final line in p.lines) {
      if (line.id.isEmpty) continue;
      final receivedCtrl = _receivedQty[line.id];
      final damagedCtrl = _damagedQty[line.id];
      if (receivedCtrl == null || damagedCtrl == null) continue;
      final parsed = _parseQty(receivedCtrl.text);
      final received = (parsed != null && parsed >= 0) ? parsed : line.qty;
      final damaged = _parseQty(damagedCtrl.text) ?? 0;
      if (damaged < 0) {
        showTopSnack(context, 'Damaged qty cannot be negative', isError: true);
        return null;
      }
      if (damaged > received) {
        showTopSnack(
          context,
          'Damaged qty cannot exceed received for ${line.itemName}',
          isError: true,
        );
        return null;
      }
      payload.add({
        'line_id': line.id,
        'received_qty': received,
        'damaged_qty': damaged,
        'return_qty': 0,
      });
    }
    if (payload.isEmpty) {
      showTopSnack(context, 'No lines to verify', isError: true);
      return null;
    }
    return payload;
  }

  Future<void> _submitReceive(TradePurchase p) async {
    final session = ref.read(sessionProvider);
    if (session == null || _saving) return;
    _ensureLineControllers(p);
    final payload = _buildVerifyPayload(p);
    if (payload == null) return;

    setState(() => _saving = true);
    try {
      final bid = session.primaryBusiness.id;
      final ds = p.deliveryStatusEnum;
      if (ds == DeliveryStatus.stockCommitted || p.isDeliveryCommitted) {
        if (mounted) {
          showTopSnack(context, 'Already committed to stock');
          context.popOrGo('/staff/deliveries');
        }
        return;
      }
      if (ds.readyForOwnerCommit) {
        if (mounted) {
          showTopSnack(
            context,
            'Waiting for owner to commit verified qty to stock',
          );
          context.popOrGo('/staff/deliveries');
        }
        return;
      }

      final arrivalNotes = _notesCtrl.text.trim().isEmpty
          ? null
          : _notesCtrl.text.trim();

      final needsArrive = ds == DeliveryStatus.pending ||
          ds == DeliveryStatus.dispatched ||
          ds == DeliveryStatus.inTransit;

      if (needsArrive) {
        await markPurchaseArrivedResilient(
          ref: ref,
          businessId: bid,
          purchaseId: p.id,
          notes: arrivalNotes,
          truckNumber: _truckCtrl.text.trim(),
          driverContact: _driverCtrl.text.trim(),
        );
      }

      if (!mounted) return;

      final body = await resilientPurchaseWrite<Map<String, dynamic>>(
        write: () => ref.read(hexaApiProvider).verifyPurchaseDelivery(
              businessId: bid,
              purchaseId: p.id,
              lines: payload,
              notes: arrivalNotes,
            ),
        ref: ref,
        businessId: bid,
        purchaseId: p.id,
        reconcileSuccess: purchasePassedVerifyGate,
        mapReconciled: (detail) => detail,
      );
      syncPurchaseStockAfterVerify(
        ref,
        purchaseId: p.id,
        verifyResponse: body,
      );
      invalidateStaffDeliverySurfaces(ref);
      ref.read(apiDegradedProvider.notifier).clear();
      if (mounted) {
        final hasDiscrepancy = payload.any(
          (row) => (row['damaged_qty'] as num? ?? 0) > 0,
        );
        showTopSnack(
          context,
          hasDiscrepancy
              ? 'Received with discrepancies. Owner will review and commit stock.'
              : 'Received as ordered. Owner will commit stock to warehouse.',
        );
        context.popOrGo('/staff/deliveries');
      }
    } catch (e) {
      if (mounted) {
        showTopSnack(
          context,
          e is DioException
              ? friendlyApiError(e)
              : 'Could not save receipt. Try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(tradePurchaseDetailProvider(widget.purchaseId));

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: const Text('Receive shipment'),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
      ),
      body: detailAsync.when(
        loading: () => const ListSkeleton(rowCount: 5),
        error: (_, __) => FriendlyLoadError(
          message: 'Could not load purchase',
          onRetry: () =>
              ref.invalidate(tradePurchaseDetailProvider(widget.purchaseId)),
        ),
        data: (p) {
          _ensureLineControllers(p);
          final ds = p.deliveryStatusEnum;
          if (ds == DeliveryStatus.stockCommitted || p.isDeliveryCommitted) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Stock already committed',
                      style: HexaDsType.heading(18),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => context.popOrGo('/staff/deliveries'),
                      child: const Text('Back'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (ds.readyForOwnerCommit) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.hourglass_top_rounded,
                        color: Color(0xFF7C3AED), size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Waiting for owner approval',
                      style: HexaDsType.heading(18),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You verified this shipment. Owner must commit to stock.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => context.popOrGo('/staff/deliveries'),
                      child: const Text('Back'),
                    ),
                  ],
                ),
              ),
            );
          }
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    _HeaderCard(purchase: p),
                    const SizedBox(height: 16),
                    Text(
                      'Verify each line',
                      style: HexaDsType.heading(16),
                    ),
                    const SizedBox(height: 8),
                    ...p.lines.map(
                      (line) => _LineReceiveTile(
                        line: line,
                        receivedCtrl: _receivedQty[line.id],
                        damagedCtrl: _damagedQty[line.id],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _truckCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Truck number (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _driverCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Driver name / contact (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Arrival notes (optional)',
                        hintText: 'Shortage, damage, partial receipt…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.2),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 16),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Enter received and damaged qty per line. '
                                'Defaults match the PO — adjust only when counts differ.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _saving
                                  ? null
                                  : () => context.popOrGo('/staff/deliveries'),
                              child: const Text('Not yet'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: _saving ? null : () => _submitReceive(p),
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.fact_check_outlined),
                              label: const Text('Arrive & verify'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.purchase});

  final TradePurchase purchase;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              purchase.humanId,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            if (purchase.supplierName != null) ...[
              const SizedBox(height: 4),
              Text(purchase.supplierName!),
            ],
            const SizedBox(height: 4),
            Text(
              df.format(purchase.purchaseDate),
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineReceiveTile extends StatelessWidget {
  const _LineReceiveTile({
    required this.line,
    required this.receivedCtrl,
    required this.damagedCtrl,
  });

  final TradePurchaseLine line;
  final TextEditingController? receivedCtrl;
  final TextEditingController? damagedCtrl;

  @override
  Widget build(BuildContext context) {
    if (receivedCtrl == null || damagedCtrl == null) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              line.itemName,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'Ordered ${line.qty.toStringAsFixed(0)} ${line.unit}',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: receivedCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Received (${line.unit})',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: damagedCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Damaged (${line.unit})',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
