import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_error_messages.dart';
import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_responsive.dart';

const _damageTypes = <String, String>{
  'damaged': 'Damaged',
  'short': 'Short delivery',
  'missing': 'Missing',
  'returned': 'Returned',
};

Future<bool?> showPurchaseDamageReportSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String purchaseId,
  String? initialItemName,
}) {
  return showHexaBottomSheet<bool>(
    context: context,
    compact: false,
    child: _PurchaseDamageReportSheet(
      purchaseId: purchaseId,
      initialItemName: initialItemName,
    ),
  );
}

class _PurchaseDamageReportSheet extends ConsumerStatefulWidget {
  const _PurchaseDamageReportSheet({
    required this.purchaseId,
    this.initialItemName,
  });

  final String purchaseId;
  final String? initialItemName;

  @override
  ConsumerState<_PurchaseDamageReportSheet> createState() =>
      _PurchaseDamageReportSheetState();
}

class _PurchaseDamageReportSheetState
    extends ConsumerState<_PurchaseDamageReportSheet> {
  final _itemCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _damageType = 'damaged';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialItemName != null &&
        widget.initialItemName!.trim().isNotEmpty) {
      _itemCtrl.text = widget.initialItemName!.trim();
    }
  }

  @override
  void dispose() {
    _itemCtrl.dispose();
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final session = ref.read(sessionProvider);
    if (session == null || _saving) return;
    final item = _itemCtrl.text.trim();
    final qty = double.tryParse(_qtyCtrl.text.trim());
    if (item.isEmpty) {
      setState(() => _error = 'Item name is required');
      return;
    }
    if (qty == null || qty <= 0) {
      setState(() => _error = 'Enter a valid quantity');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(hexaApiProvider).createPurchaseDamageReport(
            businessId: session.primaryBusiness.id,
            purchaseId: widget.purchaseId,
            itemName: item,
            qtyDamaged: qty,
            damageType: _damageType,
            notes: _notesCtrl.text,
            emitNotification: true,
            damagedItemsInBatch: 1,
          );
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      if (mounted) setState(() => _error = friendlyApiError(e));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Report damage / short delivery',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _itemCtrl,
            decoration: const InputDecoration(
              labelText: 'Item name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Quantity',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _damageTypes.entries)
                FilterChip(
                  label: Text(e.value),
                  selected: _damageType == e.key,
                  onSelected: (_) => setState(() => _damageType = e.key),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesCtrl,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? 'Submitting…' : 'Submit report'),
          ),
        ],
      ),
    );
  }
}
