import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/json_coerce.dart';
import '../../../../core/auth/auth_error_messages.dart';
import '../../../../core/providers/business_aggregates_invalidation.dart'
    show syncPurchaseStockAfterVerify;
import '../../../../core/providers/purchase_damage_reports_provider.dart';
import '../../../../core/utils/unit_utils.dart';

const _damageReasons = <String, String>{
  'torn_bag': 'Torn bag',
  'wet_damage': 'Wet damage',
  'wrong_item': 'Wrong item',
  'short_weight': 'Short weight',
  'other': 'Other',
};

Future<bool> showStaffVerificationSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String purchaseId,
  required List<Map<String, dynamic>> lines,
}) async {
  final ok = await showHexaBottomSheet<bool>(
    context: context,
    compact: false,
    padding: EdgeInsets.zero,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: HexaResponsive.adaptiveSheetMaxHeight(context),
      ),
      child: _StaffVerificationSheet(
        purchaseId: purchaseId,
        lines: lines,
      ),
    ),
  );
  return ok == true;
}

class _LineDamageState {
  bool damaged = false;
  String reason = 'torn_bag';
  final notesCtrl = TextEditingController();
}

class _StaffVerificationSheet extends ConsumerStatefulWidget {
  const _StaffVerificationSheet({
    required this.purchaseId,
    required this.lines,
  });

  final String purchaseId;
  final List<Map<String, dynamic>> lines;

  @override
  ConsumerState<_StaffVerificationSheet> createState() => _StaffVerificationSheetState();
}

class _StaffVerificationSheetState extends ConsumerState<_StaffVerificationSheet> {
  final _notesCtrl = TextEditingController();
  final _received = <String, TextEditingController>{};
  final _damagedQty = <String, TextEditingController>{};
  final _damageState = <String, _LineDamageState>{};
  bool _saving = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    for (final row in widget.lines) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final qty = coerceToDouble(row['qty']);
      final unit = row['unit']?.toString() ?? row['stock_unit']?.toString() ?? 'piece';
      _received[id] = TextEditingController(
        text: qty > 0 ? formatStockQtyForUnit(unit, qty) : '',
      );
      _damagedQty[id] = TextEditingController();
      _damageState[id] = _LineDamageState();
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final c in _received.values) {
      c.dispose();
    }
    for (final c in _damagedQty.values) {
      c.dispose();
    }
    for (final s in _damageState.values) {
      s.notesCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final session = ref.read(sessionProvider);
    if (session == null || _saving) return;

    final damagedLines = <Map<String, dynamic>>[];
    final payload = <Map<String, dynamic>>[];

    for (final row in widget.lines) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final unit = row['unit']?.toString() ?? 'piece';
      final r = double.tryParse((_received[id]?.text ?? '').trim()) ?? 0;
      final ds = _damageState[id]!;
      var d = 0.0;
      if (ds.damaged) {
        d = double.tryParse((_damagedQty[id]?.text ?? '').trim()) ?? 0;
        if (d <= 0) {
          setState(() => _submitError = 'Enter damaged quantity for flagged items');
          return;
        }
        damagedLines.add({
          'line_id': id,
          'catalog_item_id': row['catalog_item_id']?.toString(),
          'item_name': row['item_name']?.toString() ?? 'Item',
          'unit': unit,
          'damaged_qty': d,
          'reason': ds.reason,
          'notes': ds.notesCtrl.text,
        });
      }
      payload.add({
        'line_id': id,
        'received_qty': r,
        'damaged_qty': d,
        'return_qty': 0,
      });
    }

    setState(() {
      _saving = true;
      _submitError = null;
    });
    final bizId = session.primaryBusiness.id;
    final api = ref.read(hexaApiProvider);

    try {
      final body = await api.verifyPurchaseDelivery(
        businessId: bizId,
        purchaseId: widget.purchaseId,
        lines: payload,
        notes: _notesCtrl.text,
      );
      final status = (body['delivery_status']?.toString() ?? '').toLowerCase();
      syncPurchaseStockAfterVerify(
        ref,
        purchaseId: widget.purchaseId,
        verifyResponse: body,
      );

      if (damagedLines.isNotEmpty) {
        final batchN = damagedLines.length;
        for (var i = 0; i < damagedLines.length; i++) {
          final dl = damagedLines[i];
          final catId = dl['catalog_item_id']?.toString();
          await api.createPurchaseDamageReport(
            businessId: bizId,
            purchaseId: widget.purchaseId,
            itemName: dl['item_name'] as String,
            qtyDamaged: dl['damaged_qty'] as double,
            catalogItemId: catId != null && catId.isNotEmpty ? catId : null,
            unit: dl['unit'] as String?,
            reason: dl['reason'] as String,
            notes: (dl['notes'] as String?)?.trim().isNotEmpty == true
                ? dl['notes'] as String
                : null,
            emitNotification: i == damagedLines.length - 1,
            damagedItemsInBatch: batchN,
          );
        }
        ref.invalidate(pendingDamageReportsCountProvider);
        ref.invalidate(purchaseDamageReportsProvider(widget.purchaseId));
      }

      if (!mounted) return;
      setState(() {
        _submitError = status == 'stock_committed'
            ? null
            : 'Delivery saved. Stock updates apply after owner/manager commit.';
      });
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _submitError = friendlyApiError(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitError = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Delivery report',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Confirm received quantities. Flag damaged items — owner is notified.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (_submitError != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFB91C1C), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _submitError!,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7F1D1D)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            for (final row in widget.lines) ...[
              _lineRow(row),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _notesCtrl,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Delivery notes (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit delivery report'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineRow(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? '';
    final name = row['item_name']?.toString() ?? 'Item';
    final unit = row['unit']?.toString() ?? '';
    final ds = _damageState[id]!;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _numField(_received[id], 'Received qty', unit),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Damaged', style: TextStyle(fontWeight: FontWeight.w600)),
            value: ds.damaged,
            onChanged: (v) => setState(() => ds.damaged = v),
          ),
          if (ds.damaged) ...[
            _numField(_damagedQty[id], 'Damaged qty', unit),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: ds.reason,
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final e in _damageReasons.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => ds.reason = v);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ds.notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Damage notes (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _numField(TextEditingController? c, String label, String unit) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit.isNotEmpty ? unit.toUpperCase() : null,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
