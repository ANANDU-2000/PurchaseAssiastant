import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/purchase_prefill_provider.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../shared/widgets/full_screen_form_scaffold.dart';

/// Three-step trade purchase wizard (single scroll per step, fixed bottom CTA).
class PurchaseWizardPage extends ConsumerStatefulWidget {
  const PurchaseWizardPage({super.key});

  @override
  ConsumerState<PurchaseWizardPage> createState() => _PurchaseWizardPageState();
}

class _PurchaseWizardPageState extends ConsumerState<PurchaseWizardPage> {
  int _step = 0;
  bool _dirty = false;
  Timer? _draftTimer;

  late final TextEditingController _commissionCtrl;
  late final TextEditingController _paymentDaysCtrl;
  late final TextEditingController _discountCtrl;

  DateTime _purchaseDate = DateTime.now();
  String? _supplierId;
  String? _brokerId;
  int? _paymentDays;
  double? _discount;
  double? _commission;
  double? _delivered;
  double? _billty;
  double? _freight;

  final _search = TextEditingController();
  Timer? _searchDebounce;
  List<Map<String, dynamic>> _searchHits = [];

  final List<Map<String, dynamic>> _lines = [];

  @override
  void dispose() {
    _draftTimer?.cancel();
    _searchDebounce?.cancel();
    _search.dispose();
    _commissionCtrl.dispose();
    _paymentDaysCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _commissionCtrl = TextEditingController();
    _paymentDaysCtrl = TextEditingController();
    _discountCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadDraft();
      if (!mounted) return;
      final pre = ref.read(pendingPurchaseSupplierIdProvider);
      if (pre != null && pre.isNotEmpty) {
        ref.read(pendingPurchaseSupplierIdProvider.notifier).state = null;
        await _applyPrefillSupplier(pre);
      }
    });
  }

  Future<void> _applyPrefillSupplier(String id) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final s = await ref.read(hexaApiProvider).getSupplier(
            businessId: session.primaryBusiness.id,
            supplierId: id,
          );
      if (!mounted || s.isEmpty) return;
      setState(() {
        _supplierId = id;
        _applySupplierDefaults(s);
        _dirty = true;
        _scheduleDraft();
      });
    } catch (_) {}
  }

  Future<void> _loadDraft() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final d = await ref.read(hexaApiProvider).getTradePurchaseDraft(
          businessId: session.primaryBusiness.id,
        );
    if (!mounted || d == null) return;
    final p = d['payload'];
    if (p is! Map) return;
    final m = Map<String, dynamic>.from(Map<Object?, Object?>.from(p));
    setState(() {
      _step = (d['step'] as num?)?.toInt() ?? 0;
      if (m['purchase_date'] != null) {
        _purchaseDate = DateTime.tryParse(m['purchase_date'].toString()) ??
            _purchaseDate;
      }
      _supplierId = m['supplier_id']?.toString();
      _brokerId = m['broker_id']?.toString();
      _paymentDays = (m['payment_days'] as num?)?.toInt();
      _discount = (m['discount'] as num?)?.toDouble();
      _commission = (m['commission_percent'] as num?)?.toDouble();
      _commissionCtrl.text = _commission?.toString() ?? '';
      _paymentDaysCtrl.text = _paymentDays?.toString() ?? '';
      _discountCtrl.text = _discount?.toString() ?? '';
      _delivered = (m['delivered_rate'] as num?)?.toDouble();
      _billty = (m['billty_rate'] as num?)?.toDouble();
      _freight = (m['freight_amount'] as num?)?.toDouble();
      final raw = m['lines'];
      if (raw is List) {
        _lines
          ..clear()
          ..addAll(raw.map((e) => Map<String, dynamic>.from(e as Map)));
      }
      _dirty = false;
    });
  }

  Map<String, dynamic> _payload() {
    return {
      'purchase_date': DateFormat('yyyy-MM-dd').format(_purchaseDate),
      'supplier_id': _supplierId,
      'broker_id': _brokerId,
      'payment_days': _paymentDays,
      'discount': _discount,
      'commission_percent': _commission,
      'delivered_rate': _delivered,
      'billty_rate': _billty,
      'freight_amount': _freight,
      'lines': List<Map<String, dynamic>>.from(_lines),
    };
  }

  void _scheduleDraft() {
    if (!mounted) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 1200), () async {
      final session = ref.read(sessionProvider);
      if (session == null || !mounted) return;
      try {
        await ref.read(hexaApiProvider).putTradePurchaseDraft(
              businessId: session.primaryBusiness.id,
              step: _step,
              payload: _payload(),
            );
      } catch (_) {
        /* offline — ignore */
      }
    });
  }

  void _markDirty() {
    setState(() => _dirty = true);
    _scheduleDraft();
  }

  double _lineAmount(Map<String, dynamic> l) {
    final q = (l['qty'] as num?)?.toDouble() ?? 0;
    final lc = (l['landing_cost'] as num?)?.toDouble() ?? 0;
    return q * lc;
  }

  double _subtotal() {
    var s = 0.0;
    for (final l in _lines) {
      s += _lineAmount(l);
    }
    final disc = _discount ?? 0;
    if (disc > 0) {
      s *= (1 - disc / 100.0);
    }
    s += _freight ?? 0;
    return s;
  }

  Future<void> _runSearch(String q) async {
    final session = ref.read(sessionProvider);
    if (session == null || q.trim().length < 2) {
      setState(() => _searchHits = []);
      return;
    }
    try {
      final res = await ref.read(hexaApiProvider).unifiedSearch(
            businessId: session.primaryBusiness.id,
            q: q.trim(),
          );
      final items = res['catalog_items'];
      final list = <Map<String, dynamic>>[];
      if (items is List) {
        for (final e in items.take(20)) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      if (mounted) setState(() => _searchHits = list);
    } catch (_) {
      if (mounted) setState(() => _searchHits = []);
    }
  }

  void _applySupplierDefaults(Map<String, dynamic> s) {
    _paymentDays = (s['default_payment_days'] as num?)?.toInt() ?? _paymentDays;
    _discount = (s['default_discount'] as num?)?.toDouble() ?? _discount;
    _delivered =
        (s['default_delivered_rate'] as num?)?.toDouble() ?? _delivered;
    _billty = (s['default_billty_rate'] as num?)?.toDouble() ?? _billty;
    final bid = s['broker_id']?.toString();
    if (bid != null && bid.isNotEmpty) {
      _brokerId = bid;
    }
  }

  Future<void> _openRatesDialog() async {
    final dCtrl = TextEditingController(text: _delivered?.toString() ?? '');
    final bCtrl = TextEditingController(text: _billty?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set rates'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: dCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Delivered rate'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Billty rate'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        _delivered = double.tryParse(dCtrl.text);
        _billty = double.tryParse(bCtrl.text);
        _freight = (_delivered ?? 0) + (_billty ?? 0);
        _markDirty();
      });
    }
  }

  Future<void> _savePurchase() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one line item.')),
      );
      return;
    }
    final body = {
      ..._payload(),
      'lines': _lines
          .map(
            (l) => {
              'item_name': l['item_name'],
              'qty': l['qty'],
              'unit': l['unit'] ?? 'kg',
              'landing_cost': l['landing_cost'],
              if (l['selling_cost'] != null) 'selling_cost': l['selling_cost'],
              if (l['catalog_item_id'] != null)
                'catalog_item_id': l['catalog_item_id'],
            },
          )
          .toList(),
    };
    final dupBody = <String, dynamic>{
      'purchase_date': DateFormat('yyyy-MM-dd').format(_purchaseDate),
      'total_amount': _subtotal(),
      'lines': body['lines'],
    };
    if (_supplierId != null && _supplierId!.isNotEmpty) {
      dupBody['supplier_id'] = _supplierId;
    }
    try {
      final dup = await ref.read(hexaApiProvider).checkTradePurchaseDuplicate(
            businessId: session.primaryBusiness.id,
            body: dupBody,
          );
      if (dup['duplicate'] == true && mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Possible duplicate'),
            content: Text(dup['message']?.toString() ?? 'Save anyway?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
            ],
          ),
        );
        if (go != true) return;
      }
      await ref.read(hexaApiProvider).createTradePurchase(
            businessId: session.primaryBusiness.id,
            body: body,
          );
      await ref.read(hexaApiProvider).deleteTradePurchaseDraft(
            businessId: session.primaryBusiness.id,
          );
      ref.invalidate(tradePurchasesListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase saved')),
        );
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(e))),
      );
    }
  }

  Future<void> _handleLeaveRequest() async {
    if (!mounted) return;
    if (!_dirty) {
      context.pop();
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save draft?'),
        content: const Text(
          'You have unsaved changes. Save a draft to continue later?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save draft'),
          ),
        ],
      ),
    );
    if (!mounted || action == null || action == 'cancel') return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    if (action == 'save') {
      await ref.read(hexaApiProvider).putTradePurchaseDraft(
            businessId: session.primaryBusiness.id,
            step: _step,
            payload: _payload(),
          );
      if (mounted) context.pop();
    } else if (action == 'discard') {
      await ref.read(hexaApiProvider).deleteTradePurchaseDraft(
            businessId: session.primaryBusiness.id,
          );
      if (mounted) context.pop();
    }
  }

  Widget _stepHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  Widget _buildStep0(AsyncValue<List<Map<String, dynamic>>> suppliers) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _stepHeader('Purchase header'),
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Purchase date'),
          child: Text(DateFormat.yMMMd().format(_purchaseDate)),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _purchaseDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (d != null) {
                setState(() {
                  _purchaseDate = d;
                  _markDirty();
                });
              }
            },
            icon: const Icon(Icons.calendar_today_rounded),
            label: const Text('Change date'),
          ),
        ),
        suppliers.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('Could not load suppliers'),
          data: (rows) {
            return DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Supplier'),
              value: _supplierId != null &&
                      rows.any((r) => r['id']?.toString() == _supplierId)
                  ? _supplierId
                  : null,
              items: rows
                  .map(
                    (r) => DropdownMenuItem(
                      value: r['id']?.toString(),
                      child: Text(r['name']?.toString() ?? ''),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _supplierId = v;
                  if (v != null) {
                    final s = rows.firstWhere(
                      (r) => r['id']?.toString() == v,
                      orElse: () => <String, dynamic>{},
                    );
                    if (s.isNotEmpty) _applySupplierDefaults(s);
                  }
                  _markDirty();
                });
              },
            );
          },
        ),
        const SizedBox(height: 12),
        ref.watch(brokersListProvider).when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (brokers) {
                return DropdownButtonFormField<String?>(
                  decoration: const InputDecoration(labelText: 'Broker'),
                  value: _brokerId != null &&
                          brokers.any((b) => b['id']?.toString() == _brokerId)
                      ? _brokerId
                      : null,
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('None')),
                    ...brokers.map(
                      (b) => DropdownMenuItem<String?>(
                        value: b['id']?.toString(),
                        child: Text(b['name']?.toString() ?? ''),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _brokerId = v;
                      _markDirty();
                    });
                  },
                );
              },
            ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Commission %',
            hintText: 'Optional',
          ),
          keyboardType: TextInputType.number,
          controller: _commissionCtrl,
          onChanged: (t) {
            _commission = double.tryParse(t);
            _markDirty();
          },
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Payment days',
            hintText: 'Optional',
          ),
          keyboardType: TextInputType.number,
          controller: _paymentDaysCtrl,
          onChanged: (t) {
            _paymentDays = int.tryParse(t);
            _markDirty();
          },
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Header discount %',
            hintText: 'Optional',
          ),
          keyboardType: TextInputType.number,
          controller: _discountCtrl,
          onChanged: (t) {
            _discount = double.tryParse(t);
            _markDirty();
          },
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _openRatesDialog,
          icon: const Icon(Icons.local_shipping_outlined),
          label: const Text('Set rates'),
        ),
      ],
    );
  }

  Widget _buildStep1() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _stepHeader('Items'),
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Search items',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onChanged: (v) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 400), () {
              _runSearch(v);
            });
          },
        ),
        const SizedBox(height: 8),
        if (_searchHits.isNotEmpty)
          ..._searchHits.map(
            (h) => ListTile(
              title: Text(h['name']?.toString() ?? h['item_name']?.toString() ?? ''),
              subtitle: Text(h['category']?.toString() ?? ''),
              onTap: () {
                final id = h['id']?.toString();
                final name = h['name']?.toString() ?? h['item_name']?.toString() ?? 'Item';
                setState(() {
                  _lines.add({
                    'item_name': name,
                    'qty': 1.0,
                    'unit': h['default_unit']?.toString() ?? 'kg',
                    'landing_cost': 0.0,
                    'selling_cost': null,
                    if (id != null) 'catalog_item_id': id,
                  });
                  _search.clear();
                  _searchHits = [];
                  _markDirty();
                });
              },
            ),
          ),
        const SizedBox(height: 12),
        ..._lines.asMap().entries.map((e) {
          final i = e.key;
          final l = e.value;
          return Card(
            key: ValueKey('line_$i'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l['item_name']?.toString() ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _lines.removeAt(i);
                            _markDirty();
                          });
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('qty_$i'),
                          initialValue:
                              (l['qty'] as num?)?.toString() ?? '1',
                          decoration: const InputDecoration(labelText: 'Qty'),
                          keyboardType: TextInputType.number,
                          onChanged: (t) {
                            l['qty'] = double.tryParse(t) ?? 1.0;
                            _markDirty();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('unit_$i'),
                          initialValue: l['unit']?.toString() ?? 'kg',
                          decoration: const InputDecoration(labelText: 'Unit'),
                          onChanged: (t) {
                            l['unit'] = t;
                            _markDirty();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: ValueKey('land_$i'),
                    initialValue:
                        (l['landing_cost'] as num?)?.toString() ?? '0',
                    decoration: const InputDecoration(labelText: 'Landing cost'),
                    keyboardType: TextInputType.number,
                    onChanged: (t) {
                      l['landing_cost'] = double.tryParse(t) ?? 0;
                      _markDirty();
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: ValueKey('sell_$i'),
                    initialValue: l['selling_cost'] != null
                        ? (l['selling_cost'] as num).toString()
                        : '',
                    decoration: const InputDecoration(
                        labelText: 'Selling cost (optional)'),
                    keyboardType: TextInputType.number,
                    onChanged: (t) {
                      l['selling_cost'] = double.tryParse(t);
                      _markDirty();
                    },
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStep2() {
    final fmt = NumberFormat.currency(
        locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _stepHeader('Summary'),
        Text('Lines: ${_lines.length}'),
        Text('Total (approx): ${fmt.format(_subtotal())}'),
        const SizedBox(height: 12),
        ..._lines.map(
          (l) => ListTile(
            title: Text(l['item_name']?.toString() ?? ''),
            subtitle: Text(
              '${l['qty']} ${l['unit']} @ ${fmt.format((l['landing_cost'] as num?)?.toDouble() ?? 0)}',
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersListProvider);
    final title = switch (_step) {
      0 => 'Purchase · Header',
      1 => 'Purchase · Items',
      _ => 'Purchase · Summary',
    };

    Widget body;
    switch (_step) {
      case 0:
        body = _buildStep0(suppliers);
        break;
      case 1:
        body = _buildStep1();
        break;
      default:
        body = _buildStep2();
    }

    Widget bottom;
    if (_step == 0) {
      bottom = Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: () {
            setState(() {
              _step = 1;
              _scheduleDraft();
            });
          },
          child: const Text('Next'),
        ),
      );
    } else if (_step == 1) {
      bottom = Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: () {
            setState(() {
              _step = 2;
              _scheduleDraft();
            });
          },
          child: const Text('Done'),
        ),
      );
    } else {
      bottom = Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _step = 0;
                    _scheduleDraft();
                  });
                },
                child: const Text('Edit'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _savePurchase,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleLeaveRequest();
      },
      child: FullScreenFormScaffold(
        title: title,
        subtitle: 'Step ${_step + 1} of 3',
        actions: [
          IconButton(
            onPressed: _handleLeaveRequest,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
        body: body,
        bottom: bottom,
      ),
    );
  }
}
