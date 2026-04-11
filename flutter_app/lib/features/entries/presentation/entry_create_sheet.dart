import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/dashboard_provider.dart';
import '../../../core/providers/entries_list_provider.dart';
import '../../../core/providers/home_insights_provider.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import 'price_intel_strip.dart';

/// Opens the full entry form (preview → duplicate check → save).
Future<void> showEntryCreateSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: const EntryCreateSheet(),
    ),
  );
}

class _LineControllers {
  _LineControllers()
      : item = TextEditingController(),
        category = TextEditingController(),
        qty = TextEditingController(text: '1'),
        buyPrice = TextEditingController(),
        landing = TextEditingController(),
        selling = TextEditingController();

  final TextEditingController item;
  final TextEditingController category;
  final TextEditingController qty;
  final TextEditingController buyPrice;
  final TextEditingController landing;
  final TextEditingController selling;
  String unit = 'kg';

  void dispose() {
    item.dispose();
    category.dispose();
    qty.dispose();
    buyPrice.dispose();
    landing.dispose();
    selling.dispose();
  }
}

class EntryCreateSheet extends ConsumerStatefulWidget {
  const EntryCreateSheet({super.key});

  @override
  ConsumerState<EntryCreateSheet> createState() => _EntryCreateSheetState();
}

class _EntryCreateSheetState extends ConsumerState<EntryCreateSheet> {
  final _invoice = TextEditingController();
  final _transport = TextEditingController();
  final _commission = TextEditingController();
  DateTime _entryDate = DateTime.now();
  String? _supplierId;
  String? _brokerId;
  final _lines = <_LineControllers>[_LineControllers()];
  bool _busy = false;

  @override
  void dispose() {
    _invoice.dispose();
    _transport.dispose();
    _commission.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  double? _parseDouble(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  List<Map<String, dynamic>> _linesPayload() {
    return _lines.map((l) {
      final sell = _parseDouble(l.selling.text);
      final m = <String, dynamic>{
        'item_name': l.item.text.trim(),
        'qty': _parseDouble(l.qty.text) ?? 0,
        'unit': l.unit,
        'buy_price': _parseDouble(l.buyPrice.text) ?? 0,
        'landing_cost': _parseDouble(l.landing.text) ?? 0,
      };
      final cat = l.category.text.trim();
      if (cat.isNotEmpty) m['category'] = cat;
      if (sell != null) m['selling_price'] = sell;
      return m;
    }).toList();
  }

  bool _validate() {
    for (final l in _lines) {
      if (l.item.text.trim().isEmpty) return false;
      if ((_parseDouble(l.qty.text) ?? 0) <= 0) return false;
      if ((_parseDouble(l.buyPrice.text) ?? -1) < 0) return false;
      if ((_parseDouble(l.landing.text) ?? -1) < 0) return false;
    }
    return true;
  }

  Future<void> _preview() async {
    if (!_validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill item, qty, buy price, and landing for each line.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final session = ref.read(sessionProvider);
      if (session == null) return;
      final api = ref.read(hexaApiProvider);
      final body = _body(confirm: false);
      final res = await api.createEntry(businessId: session.primaryBusiness.id, body: body);
      if (!mounted) return;
      if (res['preview'] == true) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Preview'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Date: ${body['entry_date']}'),
                  const SizedBox(height: 8),
                  ...((res['lines'] as List<dynamic>?) ?? []).map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${line['item_name']} · ${line['qty']} ${line['unit']} · '
                        'landing ${line['landing_cost']} · P/L ${line['profit'] ?? '—'}',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Edit')),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _confirmSave();
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Preview failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _body({required bool confirm}) {
    final fmt = DateFormat('yyyy-MM-dd');
    final tc = _parseDouble(_transport.text);
    final comm = _parseDouble(_commission.text);
    return {
      'entry_date': fmt.format(_entryDate),
      if (_supplierId != null) 'supplier_id': _supplierId,
      if (_brokerId != null) 'broker_id': _brokerId,
      if (_invoice.text.trim().isNotEmpty) 'invoice_no': _invoice.text.trim(),
      if (tc != null) 'transport_cost': tc,
      if (comm != null) 'commission_amount': comm,
      'confirm': confirm,
      'lines': _linesPayload(),
    };
  }

  Future<void> _confirmSave() async {
    if (!_validate()) return;
    setState(() => _busy = true);
    try {
      final session = ref.read(sessionProvider);
      if (session == null) return;
      final api = ref.read(hexaApiProvider);
      final fmt = DateFormat('yyyy-MM-dd');
      final dateStr = fmt.format(_entryDate);

      final first = _lines.first;
      final dup = await api.checkDuplicate(
        businessId: session.primaryBusiness.id,
        itemName: first.item.text.trim(),
        qty: _parseDouble(first.qty.text) ?? 0,
        entryDateIso: dateStr,
      );
      final isDup = dup['duplicate'] == true;
      if (isDup && mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Possible duplicate'),
            content: const Text('An entry with the same item, qty, and date exists. Save anyway?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save anyway')),
            ],
          ),
        );
        if (go != true) {
          setState(() => _busy = false);
          return;
        }
      }

      final res = await api.createEntry(
        businessId: session.primaryBusiness.id,
        body: _body(confirm: true),
      );
      if (!mounted) return;
      if (res['id'] != null) {
        ref.invalidate(entriesListProvider);
        ref.invalidate(dashboardProvider);
        ref.invalidate(homeInsightsProvider);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry saved')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unexpected response: $res')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _entryDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _entryDate = picked);
  }

  Future<void> _addSupplierDialog() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final loc = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New supplier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name *')),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
            TextField(controller: loc, decoration: const InputDecoration(labelText: 'Location')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).createSupplier(
            businessId: session.primaryBusiness.id,
            name: name.text.trim(),
            phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
            location: loc.text.trim().isEmpty ? null : loc.text.trim(),
          );
      ref.invalidate(suppliersListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Supplier added')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final suppliersAsync = ref.watch(suppliersListProvider);
    final brokersAsync = ref.watch(brokersListProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.98,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Row(
              children: [
                Icon(Icons.edit_note_rounded, color: cs.primary, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('New purchase entry', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  tooltip: 'Add supplier',
                  onPressed: _addSupplierDialog,
                  icon: const Icon(Icons.storefront_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Entry date'),
              subtitle: Text(DateFormat.yMMMd().format(_entryDate)),
              trailing: const Icon(Icons.calendar_today_rounded),
              onTap: _busy ? null : _pickDate,
            ),
            suppliersAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('Could not load suppliers'),
              data: (list) {
                return DropdownButtonFormField<String?>(
                  // ignore: deprecated_member_use
                  value: _supplierId,
                  decoration: const InputDecoration(labelText: 'Supplier (optional)'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('None')),
                    ...list.map(
                      (s) => DropdownMenuItem<String?>(
                        value: s['id']?.toString(),
                        child: Text(s['name']?.toString() ?? ''),
                      ),
                    ),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _supplierId = v),
                );
              },
            ),
            brokersAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (list) {
                return DropdownButtonFormField<String?>(
                  // ignore: deprecated_member_use
                  value: _brokerId,
                  decoration: const InputDecoration(labelText: 'Broker (optional)'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('None')),
                    ...list.map(
                      (b) => DropdownMenuItem<String?>(
                        value: b['id']?.toString(),
                        child: Text(b['name']?.toString() ?? ''),
                      ),
                    ),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _brokerId = v),
                );
              },
            ),
            TextField(
              controller: _invoice,
              decoration: const InputDecoration(labelText: 'Invoice no.', prefixIcon: Icon(Icons.receipt_long_outlined)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _transport,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Transport cost',
                      prefixIcon: Icon(Icons.local_shipping_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _commission,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Commission',
                      prefixIcon: Icon(Icons.percent_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Line items', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ...List.generate(_lines.length, (i) => _lineCard(context, i)),
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () {
                      setState(() => _lines.add(_LineControllers()));
                    },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add line'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _preview,
                    child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Preview'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _confirmSave,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _lineCard(BuildContext context, int index) {
    final l = _lines[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Line ${index + 1}', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                if (_lines.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: _busy
                        ? null
                        : () {
                            setState(() {
                              l.dispose();
                              _lines.removeAt(index);
                            });
                          },
                  ),
              ],
            ),
            TextField(
              controller: l.item,
              decoration: const InputDecoration(labelText: 'Item *', prefixIcon: Icon(Icons.inventory_2_outlined)),
            ),
            TextField(
              controller: l.category,
              decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.category_outlined)),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: l.qty,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Qty *', prefixIcon: Icon(Icons.numbers_rounded)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'kg', label: Text('kg')),
                        ButtonSegment(value: 'box', label: Text('box')),
                        ButtonSegment(value: 'piece', label: Text('pc')),
                      ],
                      selected: {l.unit},
                      onSelectionChanged: _busy
                          ? null
                          : (s) => setState(() => l.unit = s.first),
                    ),
                  ),
                ),
              ],
            ),
            TextField(
              controller: l.buyPrice,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Buy price *', prefixIcon: Icon(Icons.currency_rupee_rounded)),
            ),
            TextField(
              controller: l.landing,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Landing cost (manual) *',
                prefixIcon: Icon(Icons.local_shipping_outlined),
              ),
            ),
            TextField(
              controller: l.selling,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Selling price', prefixIcon: Icon(Icons.sell_outlined)),
            ),
            if (index == 0)
              PriceIntelStrip(
                item: l.item,
                qty: l.qty,
                landing: l.landing,
              ),
          ],
        ),
      ),
    );
  }
}
