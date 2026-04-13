import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/contacts_hub_provider.dart';
import '../../../core/providers/dashboard_provider.dart';
import '../../../core/providers/entries_list_provider.dart';
import '../../../core/providers/home_insights_provider.dart';
import '../../../core/providers/notifications_provider.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../domain/quick_entry_parser.dart';
import 'smart_price_panel.dart';

enum _CommissionMode { totalRupees, percentOfPurchase, perUnitRupees }

/// Opens the full entry form (Preview → Confirm & save in dialog, or Save on sheet after preview token).
Future<void> showEntryCreateSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: HexaColors.surfaceCard,
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
        kgPerBag = TextEditingController(text: '50'),
        purchase = TextEditingController(),
        selling = TextEditingController(),
        stockNote = TextEditingController();

  final TextEditingController item;
  final TextEditingController category;
  final TextEditingController qty;

  /// Kg per bag when [unit] == bag.
  final TextEditingController kgPerBag;

  /// Invoice / purchase price per unit (excludes allocated entry commission — see landed cost).
  final TextEditingController purchase;
  final TextEditingController selling;
  final TextEditingController stockNote;
  String unit = 'kg';

  /// Set when user picks a row from the master catalog (sent as catalog_item_id).
  String? catalogItemId;
  String? catalogVariantId;

  void dispose() {
    item.dispose();
    category.dispose();
    qty.dispose();
    kgPerBag.dispose();
    purchase.dispose();
    selling.dispose();
    stockNote.dispose();
  }
}

class EntryCreateSheet extends ConsumerStatefulWidget {
  const EntryCreateSheet({super.key});

  @override
  ConsumerState<EntryCreateSheet> createState() => _EntryCreateSheetState();
}

class _EntryCreateSheetState extends ConsumerState<EntryCreateSheet> {
  final _invoice = TextEditingController();
  final _commission = TextEditingController();
  final _transport = TextEditingController();
  final _place = TextEditingController();
  final _quickEntry = TextEditingController();

  /// When false: one landed-cost field per line + selling; invoice/commission/transport hidden.
  bool _advancedEntryOptions = false;
  DateTime _entryDate = DateTime.now();
  String? _supplierId;
  String? _brokerId;
  final _lines = <_LineControllers>[_LineControllers()];
  bool _busy = false;

  /// Server-issued after a successful Preview; required to Save (confirm=true).
  String? _previewToken;

  _CommissionMode _commMode = _CommissionMode.totalRupees;
  bool _landingPriceSpike = false;

  void _onLandingInsight(Map<String, dynamic>? pip) {
    if (!mounted) return;
    if (pip == null || _lines.isEmpty) {
      setState(() => _landingPriceSpike = false);
      return;
    }
    final avg = pip['avg'];
    final cur = _effectiveLanding(_lines.first);
    if (avg is! num || cur <= 0) {
      setState(() => _landingPriceSpike = false);
      return;
    }
    setState(() => _landingPriceSpike = cur > avg.toDouble() * 1.15);
  }

  void _onFormFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _commission.addListener(_onFormFieldChanged);
    _quickEntry.addListener(_onFormFieldChanged);
  }

  @override
  void dispose() {
    _commission.removeListener(_onFormFieldChanged);
    _quickEntry.removeListener(_onFormFieldChanged);
    _invoice.dispose();
    _commission.dispose();
    _transport.dispose();
    _place.dispose();
    _quickEntry.dispose();
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

  double _totalQtyAcrossLines() {
    var s = 0.0;
    for (final l in _lines) {
      s += _parseDouble(l.qty.text) ?? 0;
    }
    return s;
  }

  /// Entry-level commission (₹ total) spread evenly per base unit across all lines.
  double _rawCommissionInput() => _parseDouble(_commission.text) ?? 0;

  double _commissionPerUnit() {
    final tq = _totalQtyAcrossLines();
    if (tq <= 0) return 0;
    final raw = _rawCommissionInput();
    switch (_commMode) {
      case _CommissionMode.perUnitRupees:
        return raw;
      case _CommissionMode.totalRupees:
        return raw / tq;
      case _CommissionMode.percentOfPurchase:
        var sum = 0.0;
        for (final l in _lines) {
          final q = _parseDouble(l.qty.text) ?? 0;
          final p = _parseDouble(l.purchase.text) ?? 0;
          sum += q * p;
        }
        final totalComm = sum * (raw / 100.0);
        return totalComm / tq;
    }
  }

  double? _effectiveCommissionTotalRupees() {
    final raw = _rawCommissionInput();
    final tq = _totalQtyAcrossLines();
    switch (_commMode) {
      case _CommissionMode.perUnitRupees:
        if (raw <= 0) return null;
        return raw * tq;
      case _CommissionMode.totalRupees:
        return raw > 0 ? raw : null;
      case _CommissionMode.percentOfPurchase:
        if (raw <= 0) return null;
        var sum = 0.0;
        for (final l in _lines) {
          final q = _parseDouble(l.qty.text) ?? 0;
          final p = _parseDouble(l.purchase.text) ?? 0;
          sum += q * p;
        }
        return sum * (raw / 100.0);
    }
  }

  String? _commissionSummaryLine() {
    final total = _effectiveCommissionTotalRupees();
    if (total == null || total <= 0) return null;
    final nf =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    final cpu = _commissionPerUnit();
    final nLines = _lines.length;
    return '${nf.format(total)} total commission = ${nf.format(cpu)} / unit · $nLines line${nLines == 1 ? '' : 's'}';
  }

  double _effectiveLanding(_LineControllers l) {
    final p = _parseDouble(l.purchase.text) ?? 0;
    return p + _commissionPerUnit();
  }

  List<Map<String, dynamic>> _linesPayload() {
    return _lines.map((l) {
      final sell = _parseDouble(l.selling.text);
      final land = _effectiveLanding(l);
      final m = <String, dynamic>{
        'item_name': l.item.text.trim(),
        'qty': _parseDouble(l.qty.text) ?? 0,
        'unit': l.unit,
        // Server still stores buy_price; smart entry uses landed cost only → mirror landing.
        'buy_price': land,
        'landing_cost': land,
      };
      if (l.catalogItemId != null && l.catalogItemId!.isNotEmpty) {
        m['catalog_item_id'] = l.catalogItemId;
      }
      if (l.catalogVariantId != null && l.catalogVariantId!.isNotEmpty) {
        m['catalog_variant_id'] = l.catalogVariantId;
      }
      if (l.unit == 'bag') {
        final kg = _parseDouble(l.kgPerBag.text);
        if (kg != null) m['kg_per_bag'] = kg;
        final bags = _parseDouble(l.qty.text);
        if (bags != null) m['bags'] = bags;
      }
      final cat = l.category.text.trim();
      if (cat.isNotEmpty) m['category'] = cat;
      final sn = l.stockNote.text.trim();
      if (sn.isNotEmpty) m['stock_note'] = sn;
      if (sell != null) m['selling_price'] = sell;
      return m;
    }).toList();
  }

  bool _validate() {
    for (final l in _lines) {
      if (l.item.text.trim().isEmpty) return false;
      if ((_parseDouble(l.qty.text) ?? 0) <= 0) return false;
      if ((_parseDouble(l.purchase.text) ?? -1) < 0) return false;
      if (_effectiveLanding(l) < 0) return false;
      if (l.unit == 'bag' && (_parseDouble(l.kgPerBag.text) ?? 0) <= 0) {
        return false;
      }
    }
    return true;
  }

  Future<void> _preview() async {
    if (!_validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Fill item, qty, and purchase price per line.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final session = ref.read(sessionProvider);
      if (session == null) return;
      final api = ref.read(hexaApiProvider);
      final body = _body(confirm: false);
      final res = await api.createEntry(
          businessId: session.primaryBusiness.id, body: body);
      if (!mounted) return;
      if (res['preview'] == true) {
        final tok = res['preview_token']?.toString();
        if (tok != null && tok.isNotEmpty) {
          setState(() => _previewToken = tok);
        }
        _syncLinesFromPreview(res);
        final warns = (res['warnings'] as List<dynamic>?) ?? [];
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
                  if (warns.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('Heads up', style: Theme.of(ctx).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    ...warns.map(
                      (w) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(w.toString(),
                            style: TextStyle(
                                color: Theme.of(ctx).colorScheme.tertiary)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Edit')),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  unawaited(_finalizeSaveAfterPreview());
                },
                child: const Text('Confirm & save'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _syncLinesFromPreview(Map<String, dynamic> res) {
    final raw = res['lines'] as List<dynamic>?;
    if (raw == null) return;
    for (var i = 0; i < raw.length && i < _lines.length; i++) {
      final m = raw[i];
      if (m is! Map) continue;
      final mm = Map<String, dynamic>.from(m);
      final lc = mm['landing_cost'];
      if (lc != null) {
        _lines[i].purchase.text = lc is num ? lc.toString() : lc.toString();
      }
      final cid = mm['catalog_item_id']?.toString();
      _lines[i].catalogItemId = (cid != null && cid.isNotEmpty) ? cid : null;
      final vid = mm['catalog_variant_id']?.toString();
      _lines[i].catalogVariantId = (vid != null && vid.isNotEmpty) ? vid : null;
      final kgpb = mm['kg_per_bag'];
      if (kgpb != null) {
        _lines[i].kgPerBag.text =
            kgpb is num ? kgpb.toString() : kgpb.toString();
      }
      final iname = mm['item_name']?.toString();
      if (iname != null && iname.isNotEmpty) {
        _lines[i].item.text = iname;
      }
      final cat = mm['category']?.toString();
      _lines[i].category.text = cat ?? '';
      final sn = mm['stock_note']?.toString();
      _lines[i].stockNote.text = (sn != null && sn.isNotEmpty) ? sn : '';
    }
  }

  Future<void> _pickCatalogForLine(int lineIndex) async {
    final cats = await ref.read(itemCategoriesListProvider.future);
    final items = await ref.read(catalogItemsListProvider.future);
    if (!mounted) return;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Add categories and items under Settings → Item catalog.')),
      );
      return;
    }
    final catName = <String, String>{
      for (final c in cats) c['id'].toString(): c['name'].toString(),
    };
    final l = _lines[lineIndex];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (ctx, scroll) {
            return ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final it = items[i];
                final name = it['name']?.toString() ?? '';
                final cid = it['category_id']?.toString() ?? '';
                final du = it['default_unit']?.toString();
                final sub =
                    '${catName[cid] ?? ''}${du != null && du.isNotEmpty ? ' · $du' : ''}';
                return ListTile(
                  title: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(sub),
                  onTap: () {
                    setState(() {
                      l.catalogItemId = it['id']?.toString();
                      l.item.text = name;
                      l.category.text = catName[cid] ?? '';
                      if (du != null &&
                          (du == 'kg' ||
                              du == 'box' ||
                              du == 'piece' ||
                              du == 'bag')) {
                        l.unit = du;
                      }
                    });
                    Navigator.pop(ctx);
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Map<String, dynamic> _body(
      {required bool confirm, bool forceDuplicate = false}) {
    final fmt = DateFormat('yyyy-MM-dd');
    final commTotal = _effectiveCommissionTotalRupees();
    final tr = _parseDouble(_transport.text);
    return {
      'entry_date': fmt.format(_entryDate),
      if (_supplierId != null) 'supplier_id': _supplierId,
      if (_brokerId != null) 'broker_id': _brokerId,
      if (_place.text.trim().isNotEmpty) 'place': _place.text.trim(),
      if (_invoice.text.trim().isNotEmpty) 'invoice_no': _invoice.text.trim(),
      if (commTotal != null && commTotal > 0) 'commission_amount': commTotal,
      if (_advancedEntryOptions && tr != null && tr > 0) 'transport_cost': tr,
      'confirm': confirm,
      if (confirm && _previewToken != null && _previewToken!.isNotEmpty)
        'preview_token': _previewToken,
      if (confirm && forceDuplicate) 'force_duplicate': true,
      'lines': _linesPayload(),
    };
  }

  /// One confirmation path: Preview dialog already showed lines — persist without a second sheet.
  Future<void> _finalizeSaveAfterPreview() async {
    if (!_validate()) return;
    if (_previewToken == null || _previewToken!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Tap Preview first, then Confirm & save. If you changed the form, Preview again.')),
        );
      }
      return;
    }
    setState(() => _busy = true);
    try {
      await _runSaveAttempt(forceDuplicate: false);
    } on DioException catch (e) {
      if (e.response?.statusCode == 409 && mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Possible duplicate'),
            content: const Text(
              'We found another entry with the same item, quantity, and date. Save anyway?',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save anyway')),
            ],
          ),
        );
        if (go == true) {
          try {
            await _runSaveAttempt(forceDuplicate: true);
          } catch (e2) {
            if (mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(friendlyApiError(e2))));
            }
          }
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runSaveAttempt({required bool forceDuplicate}) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final api = ref.read(hexaApiProvider);
    final fmt = DateFormat('yyyy-MM-dd');
    final dateStr = fmt.format(_entryDate);

    if (!forceDuplicate) {
      final first = _lines.first;
      final dup = await api.checkDuplicate(
        businessId: session.primaryBusiness.id,
        itemName: first.item.text.trim(),
        qty: _parseDouble(first.qty.text) ?? 0,
        entryDateIso: dateStr,
        supplierId: _supplierId,
        catalogVariantId: first.catalogVariantId,
      );
      final isDup = dup['duplicate'] == true;
      if (isDup && mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Possible duplicate'),
            content: const Text(
                'An entry with the same item, qty, and date exists. Save anyway?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save anyway')),
            ],
          ),
        );
        if (go != true) return;
        return _runSaveAttempt(forceDuplicate: true);
      }
    }

    final res = await api.createEntry(
      businessId: session.primaryBusiness.id,
      body: _body(confirm: true, forceDuplicate: forceDuplicate),
    );
    if (!mounted) return;
    if (res['id'] != null) {
      ref.invalidate(entriesListProvider);
      ref.invalidate(dashboardProvider);
      ref.invalidate(homeInsightsProvider);
      if (_landingPriceSpike) {
        final sample = _lines.isNotEmpty ? _lines.first.item.text.trim() : '';
        ref.read(notificationsProvider.notifier).addPriceSpikeAlert(
              itemSample: sample.isEmpty ? 'An item' : sample,
            );
      }
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Entry saved')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Save did not complete (no entry id from server). Try again.',
          ),
        ),
      );
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

  String _entryDateChipLabel() {
    final d = _entryDate;
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Today, ${DateFormat.MMMd().format(d)}';
    }
    return DateFormat.yMMMd().format(d);
  }

  String? _brokerIdForSupplier(
      List<Map<String, dynamic>> suppliers, String? supplierId) {
    if (supplierId == null) return null;
    for (final s in suppliers) {
      if (s['id']?.toString() == supplierId) {
        final bid = s['broker_id'];
        if (bid == null) return null;
        return bid.toString();
      }
    }
    return null;
  }

  String? _supplierLocationForSupplier(
      List<Map<String, dynamic>> suppliers, String? supplierId) {
    if (supplierId == null) return null;
    for (final s in suppliers) {
      if (s['id']?.toString() == supplierId) {
        final loc = s['location']?.toString().trim();
        if (loc == null || loc.isEmpty) return null;
        return loc;
      }
    }
    return null;
  }

  void _onSupplierChanged(String? v, List<Map<String, dynamic>> suppliers) {
    setState(() {
      _supplierId = v;
      _brokerId = _brokerIdForSupplier(suppliers, v);
    });
  }

  String? _selectedSupplierName(List<Map<String, dynamic>> suppliers) {
    if (_supplierId == null) return null;
    for (final s in suppliers) {
      if (s['id']?.toString() == _supplierId) {
        return s['name']?.toString();
      }
    }
    return null;
  }

  Future<void> _openSupplierPicker(List<Map<String, dynamic>> suppliers) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: HexaColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (ctx, scrollController) => _SupplierPickerSheet(
          scrollController: scrollController,
          suppliers: suppliers,
          selectedId: _supplierId,
          onPick: (id) {
            Navigator.pop(ctx);
            _onSupplierChanged(id, suppliers);
          },
        ),
      ),
    );
  }

  Future<void> _addBrokerDialog() async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New broker'),
        content: TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Name *'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final res = await ref.read(hexaApiProvider).createBroker(
            businessId: session.primaryBusiness.id,
            name: name.text.trim(),
          );
      ref.invalidate(brokersListProvider);
      final id = res['id']?.toString();
      if (mounted && id != null) {
        setState(() => _brokerId = id);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Broker added')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }

  void _parseQuickEntry() {
    ref.read(suppliersListProvider).when(
      data: (list) {
        final suppliers =
            list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        final names = suppliers
            .map((s) => (s['name']?.toString() ?? '').toLowerCase())
            .where((s) => s.isNotEmpty);
        unawaited(_applyQuickEntry(suppliers, names));
      },
      loading: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Still loading suppliers…')),
          );
        }
      },
      error: (_, __) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not load suppliers')),
          );
        }
      },
    );
  }

  Future<void> _enrichLineFromCatalog(_LineControllers l) async {
    final needle = l.item.text.trim().toLowerCase();
    if (needle.length < 2) return;
    try {
      final items = await ref.read(catalogItemsListProvider.future);
      final cats = await ref.read(itemCategoriesListProvider.future);
      final catNameById = {
        for (final c in cats) c['id'].toString(): c['name'].toString()
      };
      Map<String, dynamic>? best;
      var bestScore = 0;
      for (final it in items) {
        final n = (it['name']?.toString() ?? '').toLowerCase();
        if (n.isEmpty) continue;
        var score = 0;
        if (n == needle) {
          score = 100;
        } else if (n.contains(needle) || needle.contains(n)) {
          score = 60;
        } else {
          final ws = needle.split(RegExp(r'\s+')).where((e) => e.length > 1);
          if (ws.isNotEmpty && ws.every((w) => n.contains(w))) {
            score = 45;
          }
        }
        if (score > bestScore) {
          bestScore = score;
          best = it;
        }
      }
      if (best != null && bestScore >= 45 && mounted) {
        final b = best;
        final cid = b['category_id']?.toString();
        setState(() {
          l.catalogItemId = b['id']?.toString();
          if (cid != null && catNameById.containsKey(cid)) {
            l.category.text = catNameById[cid]!;
          }
          final du = b['default_unit']?.toString();
          if (du != null &&
              (du == 'kg' || du == 'box' || du == 'piece' || du == 'bag')) {
            l.unit = du;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _applyQuickEntry(List<Map<String, dynamic>> suppliers,
      Iterable<String> supplierNamesLower) async {
    final parsed = parseQuickLine(_quickEntry.text.trim(),
        supplierNamesLower: supplierNamesLower);
    if (parsed == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Try: rice vaani 43 aju · rice vaani 43 aju 46 · Basmati 50kg 1200',
            ),
          ),
        );
      }
      return;
    }
    setState(() {
      if (_lines.isEmpty) _lines.add(_LineControllers());
      final l = _lines.first;
      l.item.text = parsed.itemName;
      l.qty.text = parsed.qty.toString();
      l.unit = parsed.unit;
      l.purchase.text = parsed.landing.toString();
      l.selling.text = parsed.selling != null ? parsed.selling!.toString() : '';
      l.catalogItemId = null;
      if (parsed.supplierHint != null && suppliers.isNotEmpty) {
        final hint = parsed.supplierHint!.toLowerCase();
        Map<String, dynamic>? match;
        for (final s in suppliers) {
          final n = (s['name']?.toString() ?? '').toLowerCase();
          if (n.contains(hint) || (hint.length >= 2 && n.startsWith(hint))) {
            match = s;
            break;
          }
        }
        if (match != null) {
          _supplierId = match['id']?.toString();
          _brokerId = _brokerIdForSupplier(suppliers, _supplierId);
        }
      }
    });
    await _enrichLineFromCatalog(_lines.first);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Filled line 1 — category auto-filled when catalog matches')),
      );
    }
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
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name *')),
            TextField(
                controller: phone,
                decoration: const InputDecoration(labelText: 'Phone')),
            TextField(
                controller: loc,
                decoration: const InputDecoration(labelText: 'Location')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create')),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Supplier added')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }

  Future<void> _addCategoryFromEntry() async {
    final nameCtrl = TextEditingController();
    final emojiCtrl = TextEditingController();
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 8,
            bottom: 24 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New category',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              TextField(
                controller: emojiCtrl,
                textAlign: TextAlign.center,
                maxLength: 4,
                decoration: const InputDecoration(
                    labelText: 'Icon (emoji, optional)',
                    hintText: '🌾',
                    counterText: ''),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name *'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  final n = nameCtrl.text.trim();
                  if (n.isEmpty) return;
                  final e = emojiCtrl.text.trim();
                  Navigator.pop(ctx, e.isEmpty ? n : '$e $n');
                },
                child: const Text('Save category'),
              ),
            ],
          ),
        );
      },
    );
    nameCtrl.dispose();
    emojiCtrl.dispose();
    if (saved == null || saved.trim().isEmpty) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).createItemCategory(
            businessId: session.primaryBusiness.id,
            name: saved.trim(),
          );
      ref.invalidate(itemCategoriesListProvider);
      ref.invalidate(catalogItemsListProvider);
      ref.invalidate(contactsCategoriesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Category created — pick in line or type name')));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }

  Future<void> _addItemFromEntry() async {
    List<Map<String, dynamic>> cats = [];
    try {
      cats = await ref.read(itemCategoriesListProvider.future);
    } catch (_) {}
    if (!mounted) return;
    if (cats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Create a category first (button above).')),
      );
      return;
    }
    var selectedCat = cats.first['id']?.toString();
    final nameCtrl = TextEditingController();
    String? unit;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 8,
                bottom: 24 + MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('New catalog item',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ValueKey(selectedCat),
                    initialValue: selectedCat,
                    decoration: const InputDecoration(labelText: 'Category *'),
                    items: cats
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c['id']?.toString(),
                            child: Text(c['name']?.toString() ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setSt(() => selectedCat = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Name *'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    key: ValueKey(unit),
                    initialValue: unit,
                    decoration: const InputDecoration(
                        labelText: 'Default unit (optional)'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('—')),
                      DropdownMenuItem(value: 'kg', child: Text('kg')),
                      DropdownMenuItem(value: 'box', child: Text('box')),
                      DropdownMenuItem(value: 'piece', child: Text('pc')),
                      DropdownMenuItem(value: 'L', child: Text('L')),
                    ],
                    onChanged: (v) => setSt(() => unit = v),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Save item'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    final categoryId = selectedCat;
    if (saved != true || nameCtrl.text.trim().isEmpty || categoryId == null) {
      nameCtrl.dispose();
      return;
    }
    final session = ref.read(sessionProvider);
    if (session == null) {
      nameCtrl.dispose();
      return;
    }
    try {
      await ref.read(hexaApiProvider).createCatalogItem(
            businessId: session.primaryBusiness.id,
            categoryId: categoryId,
            name: nameCtrl.text.trim(),
            defaultUnit: unit,
          );
      ref.invalidate(catalogItemsListProvider);
      ref.invalidate(itemCategoriesListProvider);
      ref.invalidate(contactsItemsProvider);
      ref.invalidate(contactsCategoriesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Item created — use Catalog icon on line')));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
    nameCtrl.dispose();
  }

  Future<void> _addVariantFromEntry() async {
    List<Map<String, dynamic>> items = [];
    try {
      items = await ref.read(catalogItemsListProvider.future);
    } catch (_) {}
    if (!mounted) return;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Create a catalog item first, then add a variant (e.g. Basmati).')),
      );
      return;
    }
    var itemId = items.first['id']?.toString();
    final nameCtrl = TextEditingController();
    final kgCtrl = TextEditingController(text: '50');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 8,
                bottom: 24 + MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('New variant',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(itemId ?? ''),
                    initialValue: itemId,
                    decoration:
                        const InputDecoration(labelText: 'Catalog item *'),
                    items: items
                        .map(
                          (it) => DropdownMenuItem<String>(
                            value: it['id']?.toString(),
                            child: Text(it['name']?.toString() ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setSt(() => itemId = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                        labelText: 'Variant name *', hintText: 'Basmati'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: kgCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Default kg/bag (optional)', hintText: '50'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Save variant'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (ok != true || itemId == null || nameCtrl.text.trim().isEmpty) {
      nameCtrl.dispose();
      kgCtrl.dispose();
      return;
    }
    final session = ref.read(sessionProvider);
    if (session == null) {
      nameCtrl.dispose();
      kgCtrl.dispose();
      return;
    }
    try {
      final kg = double.tryParse(kgCtrl.text.trim());
      await ref.read(hexaApiProvider).createCatalogVariant(
            businessId: session.primaryBusiness.id,
            itemId: itemId!,
            name: nameCtrl.text.trim(),
            defaultKgPerBag: kg,
          );
      ref.invalidate(catalogItemsListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Variant created — pick it from the catalog line')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
    nameCtrl.dispose();
    kgCtrl.dispose();
  }

  Future<void> _pickVariantForLine(int lineIndex) async {
    final l = _lines[lineIndex];
    final cid = l.catalogItemId;
    if (cid == null || cid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Pick a catalog item first (catalog icon), then choose variant.')),
      );
      return;
    }
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final vars = await ref.read(hexaApiProvider).listCatalogVariants(
            businessId: session.primaryBusiness.id,
            itemId: cid,
          );
      if (!mounted) return;
      if (vars.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No variants yet — use Quick create → Variant')),
        );
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              ListTile(
                title: const Text('Clear variant'),
                leading: const Icon(Icons.clear_rounded),
                onTap: () {
                  setState(() => l.catalogVariantId = null);
                  Navigator.pop(ctx);
                },
              ),
              const Divider(),
              ...vars.map((v) {
                final id = v['id']?.toString() ?? '';
                final n = v['name']?.toString() ?? '';
                final kg = v['default_kg_per_bag'];
                return ListTile(
                  title: Text(n),
                  subtitle: kg != null ? Text('Default $kg kg/bag') : null,
                  onTap: () {
                    setState(() {
                      l.catalogVariantId = id;
                      if (kg != null) {
                        l.kgPerBag.text =
                            kg is num ? kg.toString() : kg.toString();
                      }
                    });
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }

  void _goToContactsForMaps() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    Future.microtask(() => router.go('/contacts'));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final suppliersAsync = ref.watch(suppliersListProvider);
    final brokersAsync = ref.watch(brokersListProvider);
    final suppliersForPlace = suppliersAsync.maybeWhen(
      data: (list) =>
          list.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      orElse: () => <Map<String, dynamic>>[],
    );
    final selectedSupplierLocation =
        _supplierLocationForSupplier(suppliersForPlace, _supplierId);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.98,
      builder: (context, scrollController) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
              children: [
                if (_landingPriceSpike) ...[
                  Container(
                    decoration: BoxDecoration(
                      color: HexaColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: HexaColors.warning),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: HexaColors.warning),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Landing price 15%+ above recent average — verify before saving.',
                              style: tt.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: HexaColors.warning),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor:
                          HexaColors.primaryLight.withValues(alpha: 0.9),
                      child: const Icon(Icons.edit_note_rounded,
                          color: HexaColors.primaryMid, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('New Entry',
                              style: tt.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(
                            'Preview → Confirm to save',
                            style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.calendar_today_rounded,
                          size: 18, color: HexaColors.primaryMid),
                      label: Text(_entryDateChipLabel(),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      onPressed: _busy ? null : _pickDate,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _quickEntry,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: 'Quick line',
                    hintText: 'rice 50kg 42 ravi  OR  ari 50kg 42 ravi',
                    prefixIcon: const Icon(Icons.bolt_rounded,
                        color: HexaColors.primaryMid),
                    suffixIcon: IconButton(
                      tooltip: 'Parse into line 1',
                      onPressed: _busy ? null : _parseQuickEntry,
                      icon: const Icon(Icons.arrow_downward_rounded),
                    ),
                  ),
                  onSubmitted: (_) => _parseQuickEntry(),
                  onChanged: (_) => setState(() {}),
                ),
                _quickLineParseChips(),
                const SizedBox(height: 16),
                Text('Supplier & Broker',
                    style:
                        tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                suppliersAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => FriendlyLoadError(
                    message: 'Could not load suppliers',
                    onRetry: () => ref.invalidate(suppliersListProvider),
                  ),
                  data: (list) {
                    final suppliers = list
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList();
                    if (suppliers.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: HexaColors.primaryLight.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                          child: const ListTile(
                            dense: true,
                            leading: Icon(Icons.info_outline_rounded),
                            title: Text('No suppliers yet — tap ＋ to add one'),
                          ),
                        ),
                      );
                    }
                    final name = _selectedSupplierName(suppliers);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _busy
                                  ? null
                                  : () => _openSupplierPicker(suppliers),
                              borderRadius: BorderRadius.circular(14),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Supplier (optional)',
                                  suffixIcon:
                                      Icon(Icons.keyboard_arrow_up_rounded),
                                ),
                                child: Text(
                                  name ?? 'Tap to search or choose',
                                  style: tt.bodyLarge?.copyWith(
                                    color: name != null
                                        ? null
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                    fontWeight: name != null
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: TextButton(
                            onPressed: _busy ? null : _addSupplierDialog,
                            child: const Text('＋ New'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                brokersAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => FriendlyLoadError(
                    message: 'Could not load brokers',
                    onRetry: () => ref.invalidate(brokersListProvider),
                  ),
                  data: (list) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            key: ValueKey(_brokerId ?? '∅'),
                            initialValue: _brokerId,
                            decoration: const InputDecoration(
                              labelText: 'Broker (from supplier or pick)',
                              helperText: 'Updates when you choose a supplier',
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                  value: null, child: Text('None')),
                              ...list.map(
                                (b) => DropdownMenuItem<String?>(
                                  value: b['id']?.toString(),
                                  child: Text(b['name']?.toString() ?? ''),
                                ),
                              ),
                            ],
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _brokerId = v),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: TextButton(
                            onPressed: _busy ? null : _addBrokerDialog,
                            child: const Text('＋ New'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (_supplierId == null || selectedSupplierLocation == null)
                  TextField(
                    controller: _place,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Purchase place / market (optional)',
                      hintText: 'e.g. Koyambedu, wholesale yard',
                      prefixIcon: Icon(Icons.place_outlined,
                          color: HexaColors.primaryMid),
                    ),
                    onChanged: (_) => setState(() {}),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Place from supplier: $selectedSupplierLocation',
                      style: tt.bodySmall
                          ?.copyWith(color: HexaColors.textSecondary),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Items',
                        style: tt.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              setState(() => _lines.add(_LineControllers()));
                            },
                      child: const Text('＋ Add line'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ...List.generate(
                    _lines.length, (i) => _lineCard(context, lineIndex: i)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.primary,
                          side: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                              width: 1.5),
                          backgroundColor:
                              Theme.of(context).brightness == Brightness.dark
                                  ? HexaColors.surfaceElevated
                                  : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                        ),
                        onPressed: _busy ? null : _preview,
                        child: _busy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Preview'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor:
                              Theme.of(context).colorScheme.onPrimary,
                          disabledBackgroundColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.45),
                          disabledForegroundColor: Colors.white70,
                        ),
                        onPressed: _busy
                            ? null
                            : (_previewToken != null &&
                                    _previewToken!.isNotEmpty
                                ? () => unawaited(_finalizeSaveAfterPreview())
                                : null),
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
                if (_previewToken == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Preview once to enable Save — we double-check the same details before saving.',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                const SizedBox(height: 8),
                ExpansionTile(
                  initiallyExpanded: false,
                  tilePadding: EdgeInsets.zero,
                  title: Text('Advanced costs & catalog tools',
                      style:
                          tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                    'Invoice, commission, transport, quick-create masters',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Advanced costs',
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        _advancedEntryOptions
                            ? 'Invoice, commission splits, transport — for traders who need the full ledger.'
                            : 'Simple: landed cost + selling only. Fastest path — add detail when you need it.',
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      value: _advancedEntryOptions,
                      onChanged: _busy
                          ? null
                          : (v) {
                              setState(() {
                                _advancedEntryOptions = v;
                                if (!v) {
                                  _commission.clear();
                                  _invoice.clear();
                                  _transport.clear();
                                }
                              });
                            },
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: HexaColors.primaryLight.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Create masters here or open the Contacts tab in the bottom navigation.',
                              style: tt.bodySmall?.copyWith(
                                  color: HexaColors.textSecondary,
                                  height: 1.35),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                ActionChip(
                                  avatar: const Icon(Icons.storefront_outlined,
                                      size: 18, color: HexaColors.primaryMid),
                                  label: const Text('Supplier'),
                                  onPressed: _busy ? null : _addSupplierDialog,
                                ),
                                ActionChip(
                                  avatar: const Icon(Icons.handshake_outlined,
                                      size: 18, color: HexaColors.primaryMid),
                                  label: const Text('Broker'),
                                  onPressed: _busy ? null : _addBrokerDialog,
                                ),
                                ActionChip(
                                  avatar: const Icon(Icons.folder_outlined,
                                      size: 18, color: HexaColors.primaryMid),
                                  label: const Text('Category'),
                                  onPressed:
                                      _busy ? null : _addCategoryFromEntry,
                                ),
                                ActionChip(
                                  avatar: const Icon(Icons.inventory_2_outlined,
                                      size: 18, color: HexaColors.primaryMid),
                                  label: const Text('Item'),
                                  onPressed: _busy ? null : _addItemFromEntry,
                                ),
                                ActionChip(
                                  avatar: const Icon(
                                      Icons.subdirectory_arrow_right_rounded,
                                      size: 18,
                                      color: HexaColors.primaryMid),
                                  label: const Text('Variant'),
                                  onPressed:
                                      _busy ? null : _addVariantFromEntry,
                                ),
                                ActionChip(
                                  avatar: const Icon(Icons.people_outline,
                                      size: 18, color: HexaColors.primaryMid),
                                  label: const Text('Contacts hub'),
                                  onPressed:
                                      _busy ? null : _goToContactsForMaps,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_advancedEntryOptions) ...[
                      TextField(
                        controller: _invoice,
                        decoration: const InputDecoration(
                            labelText: 'Invoice no.',
                            prefixIcon: Icon(Icons.receipt_long_outlined)),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _commission,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText:
                              _commMode == _CommissionMode.percentOfPurchase
                                  ? 'Commission (% of purchase value)'
                                  : _commMode == _CommissionMode.perUnitRupees
                                      ? 'Commission (₹ / unit)'
                                      : 'Commission (₹ total)',
                          prefixIcon: const Icon(Icons.percent_outlined),
                          helperText: _commMode ==
                                  _CommissionMode.percentOfPurchase
                              ? 'Percent of Σ(qty × purchase before commission). That amount is spread by quantity so each line’s landed cost includes its share.'
                              : _commMode == _CommissionMode.perUnitRupees
                                  ? 'Fixed ₹ per purchase unit on each line (same number you typed in Qty). Added to purchase → landed.'
                                  : 'Total rupees for this entry, split evenly by total quantity across lines so landed cost per unit rises equally.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<_CommissionMode>(
                        segments: const [
                          ButtonSegment(
                              value: _CommissionMode.totalRupees,
                              label: Text('₹ Total'),
                              icon: Icon(Icons.summarize_outlined)),
                          ButtonSegment(
                              value: _CommissionMode.percentOfPurchase,
                              label: Text('%'),
                              icon: Icon(Icons.percent_rounded)),
                          ButtonSegment(
                              value: _CommissionMode.perUnitRupees,
                              label: Text('₹/u'),
                              icon: Icon(Icons.straighten_rounded)),
                        ],
                        selected: {_commMode},
                        onSelectionChanged: _busy
                            ? null
                            : (s) => setState(() => _commMode = s.first),
                      ),
                      if (_commissionSummaryLine() != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _commissionSummaryLine()!,
                          style: tt.bodySmall?.copyWith(
                              color: HexaColors.textSecondary,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextField(
                        controller: _transport,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Transport (₹ total, optional)',
                          prefixIcon: Icon(Icons.local_shipping_outlined),
                          helperText:
                              'Shared costs are split across lines by value when you save.',
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(16),
                color: HexaColors.surfaceElevated,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border(
                        top: BorderSide(
                            color: HexaColors.border.withValues(alpha: 0.6),
                            width: 1)),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: _liveTotalsSummary(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  ({
    double cost,
    double kg,
    double unitQty,
    double revenue,
    double profit,
    bool mixedUnits,
    double bagQty,
  }) _rollupTotals() {
    var cost = 0.0;
    var kg = 0.0;
    var unitQty = 0.0;
    var bagQty = 0.0;
    var revenue = 0.0;
    final kinds = <String>{};
    for (final l in _lines) {
      final q = _parseDouble(l.qty.text) ?? 0;
      if (q > 0) kinds.add(l.unit);
      final land = _effectiveLanding(l);
      final sell = _parseDouble(l.selling.text);
      if (l.unit == 'bag') {
        final bags = _parseDouble(l.qty.text) ?? 0;
        final kgPb = _parseDouble(l.kgPerBag.text) ?? 0;
        final qk = bags * kgPb;
        bagQty += bags;
        cost += bags * land;
        kg += qk;
        if (sell != null) revenue += sell * qk;
      } else {
        final qq = _parseDouble(l.qty.text) ?? 0;
        cost += qq * land;
        if (l.unit == 'kg') {
          kg += qq;
        } else {
          unitQty += qq;
        }
        if (sell != null) revenue += sell * qq;
      }
    }
    final mixedUnits = kinds.length > 1;
    return (
      cost: cost,
      kg: kg,
      unitQty: unitQty,
      revenue: revenue,
      profit: revenue - cost,
      mixedUnits: mixedUnits,
      bagQty: bagQty,
    );
  }

  String _formatRollupQty(double q) {
    if (q == 0) return '0';
    if ((q - q.round()).abs() < 1e-6) return q.round().toString();
    return q.toStringAsFixed(1);
  }

  Widget _liveTotalsSummary() {
    final t = _rollupTotals();
    final nf =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final String qtyTitle;
    final String qtyBody;
    if (t.mixedUnits) {
      qtyTitle = 'Total qty (mixed)';
      final parts = <String>[];
      if (t.bagQty > 0) parts.add('${_formatRollupQty(t.bagQty)} bags');
      if (t.kg > 0) parts.add('${t.kg.toStringAsFixed(1)} kg');
      if (t.unitQty > 0) parts.add('${_formatRollupQty(t.unitQty)} u');
      qtyBody = parts.isEmpty ? '—' : parts.join(' · ');
    } else if (t.kg > 0 && t.unitQty <= 0 && t.bagQty <= 0) {
      qtyTitle = 'Total kg';
      qtyBody = t.kg.toStringAsFixed(1);
    } else if (t.bagQty > 0 && t.kg <= 0 && t.unitQty <= 0) {
      qtyTitle = 'Total bags';
      qtyBody = _formatRollupQty(t.bagQty);
    } else if (t.kg <= 0 && t.unitQty > 0 && t.bagQty <= 0) {
      qtyTitle = 'Total qty (units)';
      qtyBody = _formatRollupQty(t.unitQty);
    } else if (t.kg > 0 && t.unitQty > 0) {
      qtyTitle = 'Weight / units';
      qtyBody =
          '${t.kg.toStringAsFixed(1)} kg · ${_formatRollupQty(t.unitQty)} u';
    } else if (t.bagQty > 0) {
      qtyTitle = 'Bags / weight';
      qtyBody =
          '${_formatRollupQty(t.bagQty)} bags → ${t.kg.toStringAsFixed(1)} kg';
    } else {
      qtyTitle = 'Qty';
      qtyBody = '—';
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            'Total cost\n${nf.format(t.cost)}',
            textAlign: TextAlign.center,
            style: tt.labelSmall?.copyWith(
                color: HexaColors.costMuted, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Text(
            '$qtyTitle\n$qtyBody',
            textAlign: TextAlign.center,
            style: tt.labelSmall?.copyWith(height: 1.25),
          ),
        ),
        Expanded(
          child: Text(
            'Revenue\n${nf.format(t.revenue)}',
            textAlign: TextAlign.center,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            'Profit\n${nf.format(t.profit)}',
            textAlign: TextAlign.center,
            style: tt.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: t.profit >= 0 ? HexaColors.profit : HexaColors.loss,
            ),
          ),
        ),
      ],
    );
  }

  Widget _quickLineParseChips() {
    final raw = _quickEntry.text.trim();
    if (raw.length < 3) return const SizedBox.shrink();
    final parsed = parseQuickLine(raw, supplierNamesLower: const []);
    if (parsed == null) return const SizedBox.shrink();
    final nf =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(
            avatar: Icon(Icons.inventory_2_outlined,
                size: 18, color: Colors.white.withValues(alpha: 0.95)),
            label: Text(parsed.itemName,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: Colors.white)),
            backgroundColor: HexaColors.primaryMid,
            side: BorderSide.none,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          Chip(
            label: Text('${parsed.qty} ${parsed.unit}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            backgroundColor: HexaColors.primaryMid,
            side: BorderSide.none,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          Chip(
            avatar: Icon(Icons.payments_outlined,
                size: 18, color: Colors.white.withValues(alpha: 0.95)),
            label: Text('Buy ${nf.format(parsed.landing)}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            backgroundColor: HexaColors.primaryMid,
            side: BorderSide.none,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          if (parsed.selling != null)
            Chip(
              label: Text('Sell ${nf.format(parsed.selling!)}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              backgroundColor: HexaColors.primaryMid,
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
        ],
      ),
    );
  }

  Widget _landedCostReadout(_LineControllers l) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final land = _effectiveLanding(l);
    final cpu = _commissionPerUnit();
    final p = _parseDouble(l.purchase.text) ?? 0;
    final kgPb = l.unit == 'bag' ? (_parseDouble(l.kgPerBag.text) ?? 0) : 0.0;
    final perKg = (l.unit == 'bag' && kgPb > 0) ? land / kgPb : null;
    final title =
        l.unit == 'bag' ? 'Landed cost (auto)' : 'Landed cost / unit (auto)';
    // Bag purchases are quoted per bag — primary readout is always /bag; /kg line appears when kg/bag is set.
    final mainValue = l.unit == 'bag'
        ? '₹${land.toStringAsFixed(2)}/bag'
        : '₹${land.toStringAsFixed(2)}';
    final perKgLine = (l.unit == 'bag' && perKg != null)
        ? '₹${perKg.toStringAsFixed(2)}/kg · ${kgPb.toStringAsFixed(0)} kg/bag'
        : null;
    final caption = perKg != null
        ? 'Matches landed cost / bag above. Selling price is entered per kg (retail); profit compares cost/kg to sell/kg. Tap for breakdown.'
        : 'Not editable — purchase ₹/unit + commission share. Tap for breakdown.';
    final boxBg = isDark
        ? HexaColors.primaryLight
        : cs.primaryContainer.withValues(alpha: 0.55);
    final titleCol = isDark ? HexaColors.textSecondary : cs.onSurfaceVariant;
    final valueCol = isDark ? HexaColors.textPrimary : cs.onSurface;
    final subCol = isDark ? HexaColors.textSecondary : cs.onSurfaceVariant;
    return Material(
      color: boxBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _busy
            ? null
            : () {
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Landed cost breakdown'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Purchase / unit: ₹${p.toStringAsFixed(2)}'),
                        Text(
                            'Allocated commission / unit: ₹${cpu.toStringAsFixed(2)}'),
                        const Divider(),
                        if (perKg != null) ...[
                          Text('Landed / bag: ₹${land.toStringAsFixed(2)}'),
                          Text(
                            'Landed / kg: ₹${perKg.toStringAsFixed(2)} (${kgPb.toStringAsFixed(0)} kg/bag)',
                            style: tt.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ] else
                          Text(
                            'Landed / unit: ₹${land.toStringAsFixed(2)}',
                            style: tt.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Entry commission (field above) is divided by total quantity across all lines.',
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Close')),
                    ],
                  ),
                );
              },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: cs.primary.withValues(alpha: isDark ? 0.35 : 0.4)),
            boxShadow: HexaColors.cardShadow(context),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.balance_rounded, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: tt.labelMedium?.copyWith(
                          color: titleCol, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mainValue,
                      style: tt.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: valueCol),
                    ),
                    if (perKgLine != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        perKgLine,
                        style: tt.labelMedium?.copyWith(
                            color: subCol, fontWeight: FontWeight.w600),
                      ),
                    ],
                    Text(
                      caption,
                      style: tt.bodySmall?.copyWith(
                          color: subCol, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lineCard(BuildContext context, {required int lineIndex}) {
    final l = _lines[lineIndex];
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final unitSet = {'kg', 'bag', 'box', 'piece'};
    if (!unitSet.contains(l.unit)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => l.unit = 'kg');
      });
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: Theme.of(context).brightness == Brightness.dark ? 1 : 0,
      shadowColor: HexaColors.primaryDeep.withValues(alpha: 0.12),
      color: Theme.of(context).brightness == Brightness.dark
          ? null
          : Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: Theme.of(context).brightness == Brightness.dark
                ? HexaColors.border
                : Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Line ${lineIndex + 1}',
                    style:
                        tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                if (_lines.length > 1)
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                    onPressed: _busy
                        ? null
                        : () {
                            setState(() {
                              l.dispose();
                              _lines.removeAt(lineIndex);
                            });
                          },
                  ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: l.item,
                    onChanged: (_) => setState(() {
                      l.catalogItemId = null;
                      l.catalogVariantId = null;
                    }),
                    decoration: const InputDecoration(
                      labelText: 'Item *',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: TextButton(
                    onPressed: _busy ? null : _addItemFromEntry,
                    child: const Text('＋ New'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HexaColors.primaryMid,
                      side: const BorderSide(
                          color: HexaColors.primaryMid, width: 1.2),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 10),
                    ),
                    onPressed:
                        _busy ? null : () => _pickCatalogForLine(lineIndex),
                    icon: const Icon(Icons.list_alt_outlined, size: 20),
                    label: const Text('📋 Pick from catalog'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 10),
                      side: BorderSide(color: cs.outlineVariant),
                    ),
                    onPressed:
                        _busy ? null : () => _pickVariantForLine(lineIndex),
                    icon: const Icon(Icons.subdirectory_arrow_right_rounded,
                        size: 20),
                    label: const Text('Variant'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: l.category,
                    decoration: const InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(Icons.category_outlined)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: TextButton(
                    onPressed: _busy ? null : _addCategoryFromEntry,
                    child: const Text('＋ New'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Unit',
                style: tt.labelSmall?.copyWith(
                    color: HexaColors.textSecondary,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: HexaColors.primaryMid,
                  selectedForegroundColor: Colors.white,
                  foregroundColor: HexaColors.textSecondary,
                  side: const BorderSide(color: HexaColors.border),
                ),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment<String>(value: 'kg', label: Text('kg')),
                  ButtonSegment<String>(value: 'bag', label: Text('bag')),
                  ButtonSegment<String>(value: 'box', label: Text('box')),
                  ButtonSegment<String>(value: 'piece', label: Text('pc')),
                ],
                selected: {if (unitSet.contains(l.unit)) l.unit else 'kg'},
                onSelectionChanged: _busy
                    ? null
                    : (Set<String> next) {
                        final v = next.first;
                        setState(() => l.unit = v);
                      },
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: l.qty,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l.unit == 'bag' ? 'Bags *' : 'Qty *',
                prefixIcon: const Icon(Icons.numbers_rounded),
              ),
            ),
            if (l.unit == 'bag') ...[
              const SizedBox(height: 8),
              TextField(
                controller: l.kgPerBag,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Kg per bag *',
                  prefixIcon: Icon(Icons.scale_rounded),
                  helperText: '25 / 50 / custom — landed cost below is per bag',
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  ActionChip(
                      label: const Text('25 kg'),
                      onPressed: () => setState(() => l.kgPerBag.text = '25')),
                  ActionChip(
                      label: const Text('50 kg'),
                      onPressed: () => setState(() => l.kgPerBag.text = '50')),
                ],
              ),
            ],
            Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Stock notes (optional)',
                  style: tt.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: HexaColors.textSecondary),
                ),
                children: [
                  TextField(
                    controller: l.stockNote,
                    enabled: !_busy,
                    maxLines: 2,
                    onChanged: (_) => setState(() {}),
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Current stock before purchase',
                      prefixIcon: Icon(Icons.warehouse_outlined),
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: l.purchase,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _advancedEntryOptions
                    ? (l.unit == 'bag'
                        ? 'Purchase / bag (invoice) *'
                        : 'Purchase price / unit *')
                    : (l.unit == 'bag'
                        ? 'Landed cost / bag (₹) *'
                        : 'Landed cost / unit (₹) *'),
                prefixIcon: const Icon(Icons.currency_rupee_rounded),
                helperText: _advancedEntryOptions
                    ? (l.unit == 'bag'
                        ? 'Invoice ₹ per bag; commission field below adds to landed.'
                        : 'Invoice ₹ per unit; commission adds to landed.')
                    : (l.unit == 'bag'
                        ? 'All-in landed ₹ per bag for this line.'
                        : 'All-in landed ₹ per kg/pc — use Advanced for invoice + commission split.'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SmartPricePanel(
                item: l.item,
                qty: l.qty,
                priceController: l.purchase,
                metric: 'landing',
                currentPriceResolver: () => _effectiveLanding(l),
                onInsight: lineIndex == 0 ? _onLandingInsight : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _landedCostReadout(l),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: l.selling,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l.unit == 'bag'
                    ? 'Selling price / kg'
                    : 'Selling price / unit',
                prefixIcon: const Icon(Icons.sell_outlined),
                helperText: l.unit == 'bag'
                    ? 'Per kg (retail). Revenue = bags × kg/bag × this ₹/kg — same basis as margin below.'
                    : null,
              ),
            ),
            SmartPricePanel(
              item: l.item,
              qty: l.qty,
              priceController: l.selling,
              metric: 'selling',
            ),
            _profitRow(l),
          ],
        ),
      ),
    );
  }

  Widget _profitRow(_LineControllers l) {
    final land = _effectiveLanding(l);
    final sell = _parseDouble(l.selling.text);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    if (sell == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Profit: enter selling price to see estimate (landed cost is automatic)',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }
    final qty = _parseDouble(l.qty.text) ?? 0;
    double profit;
    double marginPct;
    var bagDetail = '';
    if (l.unit == 'bag') {
      final kgPb = _parseDouble(l.kgPerBag.text) ?? 0;
      if (kgPb <= 0) {
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Set kg per bag to see profit',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        );
      }
      final qtyKg = qty * kgPb;
      final totalCost = qty * land;
      final revenue = sell * qtyKg;
      profit = revenue - totalCost;
      marginPct = revenue > 0 ? (profit / revenue) * 100.0 : 0.0;
      final costPerKg = land / kgPb;
      bagDetail =
          ' · Cost ₹${costPerKg.toStringAsFixed(0)}/kg vs sell ₹${sell.toStringAsFixed(0)}/kg';
    } else {
      profit = (sell - land) * qty;
      marginPct = sell > 0 ? ((sell - land) / sell) * 100.0 : 0.0;
    }
    final good = marginPct >= 8;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: (good ? cs.primaryContainer : cs.errorContainer)
              .withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.show_chart_rounded,
                size: 18, color: good ? cs.primary : cs.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.unit == 'bag'
                    ? 'Line profit ₹${profit.toStringAsFixed(0)} · Margin ${marginPct.toStringAsFixed(1)}% of revenue$bagDetail'
                    : 'Profit ₹${profit.toStringAsFixed(2)} · Unit margin ${marginPct.toStringAsFixed(1)}%',
                style: tt.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: good ? cs.onPrimaryContainer : cs.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplierPickerSheet extends StatefulWidget {
  const _SupplierPickerSheet({
    required this.scrollController,
    required this.suppliers,
    required this.selectedId,
    required this.onPick,
  });

  final ScrollController scrollController;
  final List<Map<String, dynamic>> suppliers;
  final String? selectedId;
  final void Function(String?) onPick;

  @override
  State<_SupplierPickerSheet> createState() => _SupplierPickerSheetState();
}

class _SupplierPickerSheetState extends State<_SupplierPickerSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.suppliers
        : widget.suppliers
            .where(
                (s) => (s['name']?.toString() ?? '').toLowerCase().contains(q))
            .toList();
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _search,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Search suppliers',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              ListTile(
                leading: Icon(Icons.layers_clear_rounded,
                    color: widget.selectedId == null
                        ? cs.primary
                        : cs.onSurfaceVariant),
                title: const Text('None'),
                selected: widget.selectedId == null,
                onTap: () => widget.onPick(null),
              ),
              ...filtered.map((s) {
                final id = s['id']?.toString();
                final sel = id != null && id == widget.selectedId;
                return ListTile(
                  title: Text(s['name']?.toString() ?? '—'),
                  selected: sel,
                  onTap: () => widget.onPick(id),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}
