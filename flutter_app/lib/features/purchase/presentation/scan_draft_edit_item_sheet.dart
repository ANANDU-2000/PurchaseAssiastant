import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';

/// Holds catalog item id chosen from live search (same sheet session).
class ScanDraftCatalogPickHolder {
  String? catalogItemId;
}

String _mapApiDefaultUnit(String? du) {
  final u = (du ?? '').toLowerCase().trim();
  if (u == 'bag') return 'BAG';
  if (u == 'kg') return 'KG';
  if (u == 'box') return 'BOX';
  if (u == 'tin') return 'TIN';
  if (u == 'piece' || u == 'pcs' || u == 'pkt' || u == 'packet') return 'PCS';
  return 'KG';
}

/// Bottom sheet editor for one scanned line item (keyboard-safe padding + catalog autocomplete).
Future<void> editScanDraftItemRow(
  BuildContext context, {
  required WidgetRef ref,
  required int index,
  required Map<String, dynamic> item,
  required void Function(int index, Map<String, dynamic> next) onSaved,
}) async {
  final nameCtrl = TextEditingController(
    text: (item['matched_name'] ?? item['raw_name'] ?? '').toString(),
  );
  final qtyCtrl = TextEditingController(text: (item['bags'] ?? item['qty'] ?? '').toString());
  final pCtrl = TextEditingController(text: (item['purchase_rate'] ?? '').toString());
  final sCtrl = TextEditingController(text: (item['selling_rate'] ?? '').toString());
  var unit = (item['unit_type'] ?? 'KG').toString().trim().toUpperCase();
  if (unit.isEmpty) unit = 'KG';

  final unitNv = ValueNotifier<String>(unit);
  final pickHolder = ScanDraftCatalogPickHolder();

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) {
      final padBottom = MediaQuery.of(ctx).viewInsets.bottom;
      return Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: 8,
          bottom: padBottom + 16,
        ),
        child: _ScanDraftItemSheetBody(
          pickHolder: pickHolder,
          nameCtrl: nameCtrl,
          qtyCtrl: qtyCtrl,
          pCtrl: pCtrl,
          sCtrl: sCtrl,
          unitNv: unitNv,
        ),
      );
    },
  );

  final unitFinal = unitNv.value;
  unitNv.dispose();

  if (saved != true) return;
  final next = Map<String, dynamic>.from(item);
  final nm = nameCtrl.text.trim();
  if (nm.isNotEmpty) {
    next['matched_name'] = nm;
    next['raw_name'] = next['raw_name'] ?? nm;
  }
  final pickedId = pickHolder.catalogItemId?.trim();
  if (pickedId != null && pickedId.isNotEmpty) {
    next['matched_catalog_item_id'] = pickedId;
    next['matched_id'] = pickedId;
    next['confidence'] = 0.99;
    next['match_state'] = 'auto';
  }
  next['unit_type'] = unitFinal;
  final u = unitFinal;
  final q = double.tryParse(qtyCtrl.text.trim());
  if (q != null && q > 0) {
    if (u == 'BAG') {
      next['bags'] = q;
    } else {
      next['qty'] = q;
    }
  }
  final pr = double.tryParse(pCtrl.text.trim());
  if (pr != null && pr > 0) next['purchase_rate'] = pr;
  final sr = double.tryParse(sCtrl.text.trim());
  if (sr != null && sr > 0) next['selling_rate'] = sr;

  onSaved(index, next);
}

class _ScanDraftItemSheetBody extends ConsumerStatefulWidget {
  const _ScanDraftItemSheetBody({
    required this.pickHolder,
    required this.nameCtrl,
    required this.qtyCtrl,
    required this.pCtrl,
    required this.sCtrl,
    required this.unitNv,
  });

  final ScanDraftCatalogPickHolder pickHolder;
  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController pCtrl;
  final TextEditingController sCtrl;
  final ValueNotifier<String> unitNv;

  @override
  ConsumerState<_ScanDraftItemSheetBody> createState() => _ScanDraftItemSheetBodyState();
}

class _ScanDraftItemSheetBodyState extends ConsumerState<_ScanDraftItemSheetBody> {
  Timer? _debounce;
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final session = ref.read(sessionProvider);
    if (session == null || q.length < 2) {
      setState(() => _items = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final data = await ref.read(hexaApiProvider).unifiedSearch(
            businessId: session.primaryBusiness.id,
            q: q,
          );
      final raw = data['catalog_items'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw.take(12)) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      if (mounted) setState(() => _items = list);
    } on DioException {
      if (mounted) setState(() => _items = []);
    } catch (_) {
      if (mounted) setState(() => _items = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onNameChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      setState(() => _items = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () => _search(q));
  }

  void _applySuggestion(Map<String, dynamic> row) {
    final id = row['id']?.toString().trim();
    final name = (row['name'] ?? '').toString().trim();
    if (name.isEmpty) return;
    widget.nameCtrl.text = name;
    widget.pickHolder.catalogItemId = id;
    final du = _mapApiDefaultUnit(row['default_unit']?.toString());
    widget.unitNv.value = du;
    final lpp = row['last_purchase_price'];
    final lsr = row['last_selling_rate'];
    if (widget.pCtrl.text.trim().isEmpty && lpp is num && lpp > 0) {
      widget.pCtrl.text = lpp == lpp.roundToDouble() ? '${lpp.round()}' : '$lpp';
    }
    if (widget.sCtrl.text.trim().isEmpty && lsr is num && lsr > 0) {
      widget.sCtrl.text = lsr == lsr.roundToDouble() ? '${lsr.round()}' : '$lsr';
    }
    setState(() => _items = []);
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Edit item', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 10),
          TextField(
            controller: widget.nameCtrl,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Item',
              hintText: 'Type to search catalog…',
            ),
            onChanged: _onNameChanged,
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (_items.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: Material(
                elevation: 1,
                borderRadius: BorderRadius.circular(8),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final row = _items[i];
                    final name = (row['name'] ?? '').toString();
                    final unit = (row['default_unit'] ?? '—').toString();
                    final lpp = row['last_purchase_price'];
                    final rateStr = (lpp is num && lpp > 0) ? ' · last P ₹${lpp is int || lpp == lpp.roundToDouble() ? lpp.round() : lpp}' : '';
                    return ListTile(
                      dense: true,
                      title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('$unit$rateStr', maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _applySuggestion(row),
                    );
                  },
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Qty'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: widget.unitNv,
                  builder: (context, unitVal, _) {
                    return DropdownButtonFormField<String>(
                      key: ValueKey<String>(unitVal),
                      initialValue: unitVal,
                      items: const [
                        DropdownMenuItem(value: 'BAG', child: Text('bag')),
                        DropdownMenuItem(value: 'KG', child: Text('kg')),
                        DropdownMenuItem(value: 'BOX', child: Text('box')),
                        DropdownMenuItem(value: 'TIN', child: Text('tin')),
                        DropdownMenuItem(value: 'PCS', child: Text('piece')),
                      ],
                      onChanged: (v) {
                        if (v != null) widget.unitNv.value = v;
                      },
                      decoration: const InputDecoration(labelText: 'Unit'),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.pCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Purchase rate'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: widget.sCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(labelText: 'Selling rate'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
