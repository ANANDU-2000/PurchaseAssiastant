import 'package:flutter/material.dart';

/// Bottom sheet editor for one scanned line item (keyboard-safe padding).
Future<void> editScanDraftItemRow(
  BuildContext context, {
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Edit item', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 10),
              TextField(
                controller: nameCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Item'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Qty'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatefulBuilder(
                      builder: (context, setLocal) {
                        return DropdownButtonFormField<String>(
                          value: unit,
                          items: const [
                            DropdownMenuItem(value: 'BAG', child: Text('bag')),
                            DropdownMenuItem(value: 'KG', child: Text('kg')),
                            DropdownMenuItem(value: 'BOX', child: Text('box')),
                            DropdownMenuItem(value: 'TIN', child: Text('tin')),
                            DropdownMenuItem(value: 'PCS', child: Text('piece')),
                          ],
                          onChanged: (v) => setLocal(() => unit = v ?? unit),
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
                      controller: pCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Purchase rate'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: sCtrl,
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
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  if (saved != true) return;
  final next = Map<String, dynamic>.from(item);
  final nm = nameCtrl.text.trim();
  if (nm.isNotEmpty) {
    next['matched_name'] = nm;
    next['raw_name'] = next['raw_name'] ?? nm;
  }
  next['unit_type'] = unit;
  final q = double.tryParse(qtyCtrl.text.trim());
  if (q != null && q > 0) {
    if (unit == 'BAG') {
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
