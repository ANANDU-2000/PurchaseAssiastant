import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/fastapi_error.dart';
import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/calc_engine.dart';
import '../../../core/strict_decimal.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/business_aggregates_invalidation.dart'
    show invalidatePurchaseWorkspace, invalidateWorkspaceSeedData;
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/prefs_provider.dart';
import '../../../core/services/offline_store.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/notifications/local_notifications_service.dart';
import '../../purchase/domain/purchase_draft.dart';
import '../../purchase/state/purchase_draft_provider.dart';
import '../../../shared/widgets/inline_search_field.dart';
import 'widgets/add_item_entry_page.dart';
import 'widgets/purchase_saved_sheet.dart';

class PurchaseEntryWizardV2 extends ConsumerStatefulWidget {
  const PurchaseEntryWizardV2({
    super.key,
    this.editingId,
    this.initialCatalogItemId,
    this.initialDraft,
  });

  final String? editingId;
  final String? initialCatalogItemId;
  /// Seeds the wizard after OCR / external flows (skipped when editing).
  final PurchaseDraft? initialDraft;

  @override
  ConsumerState<PurchaseEntryWizardV2> createState() =>
      _PurchaseEntryWizardV2State();
}

class _PurchaseEntryWizardV2State extends ConsumerState<PurchaseEntryWizardV2> {
  bool _isBootstrapping = false;
  String? _editBootstrapError;
  bool _isSaving = false;
  bool _formDirty = false;
  String? _previewHumanId;
  String? _editHumanId;
  String? _loadedDerivedStatus;
  double? _loadedRemaining;
  String? _inlineSaveError;
  String? _supplierFieldError;
  List<Map<String, dynamic>>? _lastGoodSuppliers;
  bool _triedEmptyCatalogBootstrap = false;
  bool _catalogLinePrefillOpened = false;
  /// When catalog line defaults reduce suppliers to a single option, we auto-pick once per signature.
  String? _lastAutoSupplierFromCatalogSig;
  /// Last good catalog snapshot for stale-while-revalidate UX.
  List<Map<String, dynamic>>? _lastCatalogSnapshot;

  /// [tradeSupplierBrokerMap] top suppliers for current line catalog ids (hint only).
  String? _historyHintKey;
  Future<List<String>>? _historySupplierNamesFuture;
  Timer? _draftDebounce;

  /// Latest [purchase_date] per supplier from recent trade list (for autocomplete sort).
  Map<String, DateTime> _supplierLastPurchaseById = {};

  /// Ignore stale async work when the user picks another supplier before requests finish.
  int _supplierApplySeq = 0;

  final _supplierSectionKey = GlobalKey();
  final _itemsSectionKey = GlobalKey();
  final _addItemFocus = FocusNode();

  final _supplierCtrl = TextEditingController();
  final _brokerCtrl = TextEditingController();
  final _paymentDaysCtrl = TextEditingController();
  final _headerDiscCtrl = TextEditingController();
  final _commissionCtrl = TextEditingController();
  final _deliveredRateCtrl = TextEditingController();
  final _billtyRateCtrl = TextEditingController();
  final _freightCtrl = TextEditingController();
  final _invoiceCtrl = TextEditingController();
  String _freightType = 'separate';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final notifier = ref.read(purchaseDraftProvider.notifier);
    if (widget.editingId != null && widget.editingId!.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _isBootstrapping = true;
        _editBootstrapError = null;
      });
      Map<String, dynamic>? raw;
      try {
        raw = await notifier.loadFromEdit(widget.editingId!);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _editBootstrapError = friendlyApiError(e);
          _isBootstrapping = false;
        });
        return;
      }
      if (!mounted) return;
      if (raw == null) {
        setState(() {
          _editBootstrapError = 'Could not load this purchase. '
              'Check that you are signed in and try again.';
          _isBootstrapping = false;
        });
        return;
      }
      _editHumanId = raw['human_id']?.toString();
      _loadedDerivedStatus = raw['derived_status']?.toString();
      _loadedRemaining = (raw['remaining'] as num?)?.toDouble();
      if (!mounted) return;
      _syncControllersFromDraft();
      setState(() => _isBootstrapping = false);
    } else {
      if (!mounted) return;
      notifier.reset();
      if (widget.initialDraft != null) {
        ref.read(purchaseDraftProvider.notifier).replaceDraft(widget.initialDraft!);
      } else {
        await _maybeRestoreDraft();
      }
      if (!mounted) return;
      ref.read(purchaseDraftProvider.notifier).setInvoiceText('');
      _syncControllersFromDraft();
      Future.microtask(() {
        if (!mounted) return;
        ref.invalidate(catalogItemsListProvider);
      });
    }
    if (!mounted) return;
    // Defer heavy I/O — first paint is sync path above only.
    unawaited(Future<void>(() async {
      if (!mounted) return;
      await _prefetchNextHumanId();
      if (!mounted) return;
      await _openCatalogLinePrefillIfNeeded();
      if (!mounted) return;
      await _ensureCatalogSeedIfEmpty();
      if (!mounted) return;
      await _prefetchSupplierLastPurchasesMap();
    }));
  }

  void _syncControllersFromDraft() {
    final d = ref.read(purchaseDraftProvider);
    _freightType = d.freightType;
    _supplierCtrl.text = d.supplierName ?? '';
    _brokerCtrl.text = d.brokerName ?? '';
    _paymentDaysCtrl.text = d.paymentDays != null ? '${d.paymentDays}' : '';
    _headerDiscCtrl.text = d.headerDiscountPercent != null
        ? d.headerDiscountPercent!.toStringAsFixed(2)
        : '';
    _commissionCtrl.text = d.commissionPercent != null
        ? d.commissionPercent!.toStringAsFixed(2)
        : '';
    _deliveredRateCtrl.text = d.deliveredRate != null
        ? d.deliveredRate!.toStringAsFixed(2)
        : '';
    _billtyRateCtrl.text =
        d.billtyRate != null ? d.billtyRate!.toStringAsFixed(2) : '';
    _freightCtrl.text =
        d.freightAmount != null ? d.freightAmount!.toStringAsFixed(2) : '';
    _invoiceCtrl.text = d.invoiceNumber ?? '';
  }

  Future<void> _ensureCatalogSeedIfEmpty() async {
    if (_triedEmptyCatalogBootstrap) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final catalog = await ref.read(catalogItemsListProvider.future);
      if (!mounted) return;
      if (catalog.isNotEmpty) return;
      _triedEmptyCatalogBootstrap = true;
      await ref.read(hexaApiProvider).bootstrapWorkspace();
      if (!mounted) return;
      invalidateWorkspaceSeedData(ref);
      ref.invalidate(catalogItemsListProvider);
      ref.invalidate(suppliersListProvider);
    } catch (_) {
      _triedEmptyCatalogBootstrap = true;
    }
  }

  Future<void> _openCatalogLinePrefillIfNeeded() async {
    final cid = widget.initialCatalogItemId;
    if (cid == null || cid.isEmpty) return;
    if (widget.editingId != null && widget.editingId!.isNotEmpty) return;
    if (_catalogLinePrefillOpened) return;
    final draft = ref.read(purchaseDraftProvider);
    if (draft.supplierId == null || draft.supplierId!.isEmpty) return;
    if (draft.lines.isNotEmpty) return;
    _catalogLinePrefillOpened = true;
    try {
      final catalog = await ref.read(catalogItemsListProvider.future);
      if (!mounted) return;
      final row = _catalogRowById(catalog, cid);
      if (row == null) return;
      final label = row['name']?.toString() ?? '';
      final unit = row['default_purchase_unit']?.toString() ??
          row['default_unit']?.toString() ??
          'kg';
      var land = 0.0;
      final lp = row['default_landing_cost'];
      if (lp is num && lp > 0) land = lp.toDouble();
      final kpb = row['default_kg_per_bag'];
      final kpbD = kpb is num && kpb > 0 ? kpb.toDouble() : null;
      final uNorm = unit.trim().toLowerCase();
      final tax = row['tax_percent'];
      final initial = <String, dynamic>{
        'catalog_item_id': cid,
        'item_name': label,
        'qty': 1.0,
        'unit': unit,
        if (tax is num && tax > 0) 'tax_percent': tax.toDouble(),
      };
      if ((uNorm == 'bag' || uNorm == 'sack') && kpbD != null && land > 0) {
        initial['kg_per_unit'] = kpbD;
        initial['landing_cost_per_kg'] = land / kpbD;
        initial['landing_cost'] = land;
      } else {
        initial['landing_cost'] = land;
      }
      if (!mounted) return;
      await _openItemSheet(catalog, initialOverride: initial);
    } catch (_) {}
  }

  Map<String, dynamic>? _catalogRowById(
    List<Map<String, dynamic>> catalog,
    String id,
  ) {
    for (final m in catalog) {
      if (m['id']?.toString() == id) return m;
    }
    return null;
  }

  Future<void> _prefetchNextHumanId() async {
    if (widget.editingId != null && widget.editingId!.isNotEmpty) return;
    final s = ref.read(sessionProvider);
    if (s == null) return;
    try {
      final id = await ref
          .read(hexaApiProvider)
          .nextTradePurchaseHumanId(businessId: s.primaryBusiness.id);
      if (!mounted) return;
      if (id.isNotEmpty) setState(() => _previewHumanId = id);
    } catch (_) {}
  }

  static const _draftKeyV1 = 'draft_trade_purchase_v1';

  String? _draftPrefsKey() {
    final s = ref.read(sessionProvider);
    if (s == null) return null;
    return '${_draftKeyV1}_${s.primaryBusiness.id}';
  }

  Future<void> _maybeRestoreDraft() async {
    if (widget.editingId != null && widget.editingId!.isNotEmpty) return;
    final k = _draftPrefsKey();
    final s0 = ref.read(sessionProvider);
    if (s0 == null || k == null) return;
    final bid = s0.primaryBusiness.id;
    final fromHive = OfflineStore.getPurchaseWizardDraft(bid);
    Future<void> applyMap(Map<String, dynamic> o) async {
      ref.read(purchaseDraftProvider.notifier).applyFromPrefsMap(o);
      if (!mounted) return;
      _syncControllersFromDraft();
      setState(() => _formDirty = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Restored your unsaved purchase draft')),
        );
      }
    }

    if (fromHive != null && fromHive.isNotEmpty) {
      try {
        final o = jsonDecode(fromHive);
        if (o is Map<String, dynamic>) {
          await applyMap(o);
          return;
        }
        if (o is Map) {
          await applyMap(Map<String, dynamic>.from(o));
          return;
        }
      } catch (_) {}
    }

    final p = ref.read(sharedPreferencesProvider);
    final prefsStr = p.getString(k);
    if (prefsStr == null || prefsStr.isEmpty) return;
    try {
      final o = jsonDecode(prefsStr);
      if (o is! Map) return;
      final m = Map<String, dynamic>.from(o);
      await applyMap(m);
      await OfflineStore.putPurchaseWizardDraft(bid, prefsStr);
      await p.remove(k);
    } catch (_) {}
  }

  void _onDraftChanged() {
    if (widget.editingId != null && widget.editingId!.isNotEmpty) return;
    if (!mounted) return;
    if (!_formDirty) setState(() => _formDirty = true);
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _flushDraftToPrefs();
    });
  }

  void _flushDraftToPrefs() {
    if (widget.editingId != null && widget.editingId!.isNotEmpty) return;
    final k = _draftPrefsKey();
    final s = ref.read(sessionProvider);
    if (s == null || k == null) return;
    final bid = s.primaryBusiness.id;
    final p = ref.read(sharedPreferencesProvider);
    final json =
        jsonEncode(ref.read(purchaseDraftProvider.notifier).toPrefsMap());
    unawaited(p.setString(k, json));
    unawaited(OfflineStore.putPurchaseWizardDraft(bid, json));
  }

  Future<void> _clearDraftInPrefs() async {
    final k = _draftPrefsKey();
    final s = ref.read(sessionProvider);
    if (s == null || k == null) return;
    final bid = s.primaryBusiness.id;
    final p = ref.read(sharedPreferencesProvider);
    await p.remove(k);
    await OfflineStore.clearPurchaseWizardDraft(bid);
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    if (widget.editingId == null || widget.editingId!.isEmpty) {
      final s = ref.read(sessionProvider);
      if (s != null) {
        final k = '${_draftKeyV1}_${s.primaryBusiness.id}';
        final bid = s.primaryBusiness.id;
        final p = ref.read(sharedPreferencesProvider);
        final json =
            jsonEncode(ref.read(purchaseDraftProvider.notifier).toPrefsMap());
        unawaited(p.setString(k, json));
        unawaited(OfflineStore.putPurchaseWizardDraft(bid, json));
      }
    }
    _addItemFocus.dispose();
    _supplierCtrl.dispose();
    _brokerCtrl.dispose();
    _paymentDaysCtrl.dispose();
    _headerDiscCtrl.dispose();
    _commissionCtrl.dispose();
    _deliveredRateCtrl.dispose();
    _billtyRateCtrl.dispose();
    _freightCtrl.dispose();
    _invoiceCtrl.dispose();
    super.dispose();
  }

  String _duePreviewText() {
    final pd = int.tryParse(_paymentDaysCtrl.text.trim());
    if (pd == null || pd < 0) return 'Due: —';
    final d0 = ref.read(purchaseDraftProvider).purchaseDate ?? DateTime.now();
    final d = d0.add(Duration(days: pd));
    return 'Due: ${DateFormat('dd MMM yyyy').format(d)}';
  }

  String _supplierMapLabel(Map<String, dynamic> m) {
    for (final k in [
      'name',
      'legal_name',
      'display_name',
      'company_name',
      'trading_name',
    ]) {
      final v = m[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return m['id']?.toString() ?? '';
  }

  String _supplierRowId(Map<String, dynamic> m) {
    final v = m['id'] ?? m['supplier_id'];
    return v?.toString().trim() ?? '';
  }

  DateTime? _parsePurchaseDateOnly(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw.toString().trim());
  }

  Future<void> _prefetchSupplierLastPurchasesMap() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final list = await ref.read(hexaApiProvider).listTradePurchases(
            businessId: session.primaryBusiness.id,
            limit: 500,
          );
      final map = <String, DateTime>{};
      for (final p in list) {
        final sid = p['supplier_id']?.toString().trim();
        if (sid == null || sid.isEmpty) continue;
        final d = _parsePurchaseDateOnly(p['purchase_date']);
        if (d == null) continue;
        final cur = map[sid];
        if (cur == null || d.isAfter(cur)) map[sid] = d;
      }
      if (mounted) setState(() => _supplierLastPurchaseById = map);
    } catch (_) {
      if (mounted) setState(() => _supplierLastPurchaseById = {});
    }
  }

  List<Map<String, dynamic>> _sortSuppliersByPurchaseRecency(
    List<Map<String, dynamic>> list,
  ) {
    if (list.isEmpty) return list;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cutoff = today.subtract(const Duration(days: 30));
    int tier(Map<String, dynamic> m) {
      final id = _supplierRowId(m);
      final d = _supplierLastPurchaseById[id];
      if (d == null) return 2;
      final dayOnly = DateTime(d.year, d.month, d.day);
      if (!dayOnly.isBefore(cutoff)) return 0;
      return 1;
    }

    DateTime? lastDay(Map<String, dynamic> m) =>
        _supplierLastPurchaseById[_supplierRowId(m)];

    final sorted = List<Map<String, dynamic>>.from(list);
    sorted.sort((a, b) {
      final ta = tier(a);
      final tb = tier(b);
      if (ta != tb) return ta.compareTo(tb);
      final da = lastDay(a);
      final db = lastDay(b);
      if (da != null && db != null) return db.compareTo(da);
      if (da != null) return -1;
      if (db != null) return 1;
      return _supplierMapLabel(a)
          .toLowerCase()
          .compareTo(_supplierMapLabel(b).toLowerCase());
    });
    return sorted;
  }

  String _supplierSearchSubtitle(Map<String, dynamic> m) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cutoff = today.subtract(const Duration(days: 30));
    final id = _supplierRowId(m);
    final d = _supplierLastPurchaseById[id];
    if (d != null) {
      final dayOnly = DateTime(d.year, d.month, d.day);
      if (!dayOnly.isBefore(cutoff)) {
        return 'Last: ${DateFormat('dd MMM yyyy').format(d)}';
      }
    }
    final phone = m['phone']?.toString().trim();
    if (phone != null && phone.isNotEmpty) return phone;
    final gst = m['gst_number']?.toString().trim();
    if (gst != null && gst.isNotEmpty) return gst;
    return '';
  }

  Future<void> _openQuickSupplierCreate(
    List<Map<String, dynamic>> lookupList,
  ) async {
    final result = await context.push<Map<String, dynamic>?>(
      '/suppliers/quick-create',
    );
    if (!mounted) return;
    final id = result?['id']?.toString();
    if (id == null || id.isEmpty) return;
    ref.invalidate(suppliersListProvider);
    final label = (result?['name']?.toString() ?? '').trim();
    try {
      final list = await ref.read(suppliersListProvider.future);
      if (!mounted) return;
      await _applySupplierSelectionAsync(
        list,
        InlineSearchItem(
          id: id,
          label: label.isNotEmpty ? label : 'Supplier',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      await _applySupplierSelectionAsync(
        lookupList,
        InlineSearchItem(
          id: id,
          label: label.isNotEmpty ? label : 'Supplier',
        ),
      );
    }
  }

  Future<void> _openQuickBrokerCreate(
    List<Map<String, dynamic>> lookupList,
  ) async {
    final result = await context.push<Map<String, dynamic>?>(
      '/brokers/quick-create',
    );
    if (!mounted) return;
    final id = result?['id']?.toString();
    if (id == null || id.isEmpty) return;
    ref.invalidate(brokersListProvider);
    final label = (result?['name']?.toString() ?? '').trim();
    try {
      final list = await ref.read(brokersListProvider.future);
      if (!mounted) return;
      _applyBrokerSelection(
        list.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        InlineSearchItem(
          id: id,
          label: label.isNotEmpty ? label : 'Broker',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _applyBrokerSelection(
        lookupList,
        InlineSearchItem(
          id: id,
          label: label.isNotEmpty ? label : 'Broker',
        ),
      );
    }
  }

  String _apiDateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Top-3 suppliers by aggregated [deals] across all [catalogIds] (hint only).
  Future<List<String>> _fetchSupplierHistoryHintsForCatalogs(
      String businessId, Set<String> catalogIds) async {
    if (catalogIds.isEmpty) return [];
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 365));
    final m = await ref.read(hexaApiProvider).tradeSupplierBrokerMap(
          businessId: businessId,
          from: _apiDateOnly(from),
          to: _apiDateOnly(now),
        );
    final rows = (m['rows'] as List?) ?? const [];
    final bySupplierId = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      if (r is! Map) continue;
      final row = Map<String, dynamic>.from(r);
      final cid = row['catalog_item_id']?.toString();
      if (cid == null || !catalogIds.contains(cid)) continue;
      final sid = row['supplier_id']?.toString().trim() ?? '';
      if (sid.isEmpty) continue;
      final name = row['supplier_name']?.toString().trim() ?? '';
      final deals = (row['deals'] as num?)?.toInt() ?? 0;
      final ex = bySupplierId[sid];
      if (ex == null) {
        bySupplierId[sid] = {'name': name, 'deals': deals};
      } else {
        ex['deals'] = (ex['deals'] as int) + deals;
      }
    }
    final list = bySupplierId.entries.toList()
      ..sort((a, b) => (b.value['deals'] as int)
          .compareTo(a.value['deals'] as int));
    final names = <String>[];
    for (final e in list.take(3)) {
      final n = e.value['name'] as String;
      if (n.isNotEmpty) names.add(n);
    }
    return names;
  }

  /// Restricts supplier pick to intersection of [default_supplier_ids] on every line
  /// that has a catalog item with non-empty defaults. If any such line has no defaults,
  /// fall back to the full list. Empty intersection falls back to full list.
  List<Map<String, dynamic>> _filterSuppliersByCatalogLineDefaults(
    List<Map<String, dynamic>> allSuppliers,
    List<Map<String, dynamic>> catalog,
  ) {
    final draft = ref.read(purchaseDraftProvider);
    Set<String>? allowed;
    for (final line in draft.lines) {
      final cid = line.catalogItemId;
      if (cid == null || cid.isEmpty) continue;
      Map<String, dynamic>? item;
      for (final c in catalog) {
        if (c['id']?.toString() == cid) {
          item = c;
          break;
        }
      }
      if (item == null) continue;
      final raw = item['default_supplier_ids'] as List?;
      if (raw == null || raw.isEmpty) {
        allowed = null;
        break;
      }
      final sset = raw.map((e) => e.toString()).toSet();
      allowed = allowed == null ? sset : allowed.intersection(sset);
    }
    if (allowed == null) return allSuppliers;
    if (allowed.isEmpty) return allSuppliers;
    final allow = allowed;
    final filtered = allSuppliers
        .where((m) => allow.contains(_supplierRowId(m)))
        .toList();
    return filtered.isEmpty ? allSuppliers : filtered;
  }

  void _applySupplierSelection(
    List<Map<String, dynamic>> list,
    InlineSearchItem it,
  ) {
    unawaited(_applySupplierSelectionAsync(list, it));
  }

  Future<void> _applySupplierSelectionAsync(
    List<Map<String, dynamic>> list,
    InlineSearchItem it,
  ) async {
    if (it.id.isEmpty) return;
    final seq = ++_supplierApplySeq;
    final want = it.id.trim().toLowerCase();
    Map<String, dynamic>? row;
    for (final m in list) {
      if (_supplierRowId(m).toLowerCase() == want) {
        row = Map<String, dynamic>.from(m);
        break;
      }
    }
    row ??= <String, dynamic>{'id': it.id, 'name': it.label};
    final session = ref.read(sessionProvider);
    if (session != null) {
      try {
        final fresh = await ref.read(hexaApiProvider).getSupplier(
              businessId: session.primaryBusiness.id,
              supplierId: it.id,
            );
        if (fresh.isNotEmpty) {
          row = fresh;
        }
      } catch (_) {}
    }
    if (!mounted || seq != _supplierApplySeq) return;
    final supplierRow = row!;
    ref
        .read(purchaseDraftProvider.notifier)
        .applySupplierSelection(supplierRow, it.id, it.label);
    if (session != null) {
      try {
        final autofill = await ref.read(hexaApiProvider).tradeLastSupplierAutofill(
              businessId: session.primaryBusiness.id,
              supplierId: it.id,
            );
        if (!mounted || seq != _supplierApplySeq) return;
        ref
            .read(purchaseDraftProvider.notifier)
            .applyLastSupplierTradeAutofill(autofill);
        final src = autofill['source']?.toString();
        final abid = autofill['broker_id']?.toString().trim();
        if (abid != null && abid.isNotEmpty) {
          try {
            final b = await ref.read(hexaApiProvider).getBroker(
                  businessId: session.primaryBusiness.id,
                  brokerId: abid,
                );
            if (!mounted || seq != _supplierApplySeq) return;
            final nm = b['name']?.toString().trim();
            ref.read(purchaseDraftProvider.notifier).setBroker(
                  abid,
                  (nm != null && nm.isNotEmpty) ? nm : 'Broker',
                  fromSupplier: false,
                );
          } catch (_) {
            if (!mounted || seq != _supplierApplySeq) return;
            ref.read(purchaseDraftProvider.notifier).setBroker(
                  abid,
                  'Broker',
                  fromSupplier: false,
                );
          }
        } else if (src == 'supplier_last_trade') {
          ref.read(purchaseDraftProvider.notifier).setBroker(null, null);
        }
      } catch (_) {}
    }
    if (!mounted || seq != _supplierApplySeq) return;
    _syncControllersFromDraft();
    setState(() {
      _supplierFieldError = null;
      _inlineSaveError = null;
    });
    _onDraftChanged();
    HapticFeedback.selectionClick();
    unawaited(_openCatalogLinePrefillIfNeeded());
  }

  String _brokerRowId(Map<String, dynamic> m) {
    final v = m['id'] ?? m['broker_id'];
    return v?.toString().trim() ?? '';
  }

  String _brokerMapLabel(Map<String, dynamic> m) {
    final v = m['name']?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
    return _brokerRowId(m);
  }

  void _applyBrokerSelection(
    List<Map<String, dynamic>> brokers,
    InlineSearchItem it,
  ) {
    if (it.id.isEmpty) return;
    ref.read(purchaseDraftProvider.notifier).setBroker(
          it.id,
          it.label,
          fromSupplier: false,
        );
    setState(() {});
    _onDraftChanged();
  }

  Map<String, dynamic>? _supplierRowById(String supplierId) {
    final list = _lastGoodSuppliers ??
        ref.read(suppliersListProvider).valueOrNull ??
        const <Map<String, dynamic>>[];
    final want = supplierId.trim().toLowerCase();
    for (final m in list) {
      if (_supplierRowId(m).toLowerCase() == want) return m;
    }
    return null;
  }

  void _applyBrokerFromSupplierRow() {
    final draft = ref.read(purchaseDraftProvider);
    final sid = draft.supplierId;
    if (sid == null || sid.isEmpty) return;
    final row = _supplierRowById(sid);
    final bid = row?['broker_id']?.toString();
    if (bid == null || bid.isEmpty) return;
    final brokers = ref.read(brokersListProvider).valueOrNull ?? const [];
    String? name;
    for (final b in brokers) {
      if (_brokerRowId(b).toLowerCase() == bid.toLowerCase()) {
        name = _brokerMapLabel(b);
        break;
      }
    }
    ref.read(purchaseDraftProvider.notifier).setBroker(
          bid,
          name ?? 'Broker',
          fromSupplier: true,
        );
    setState(() {});
    _onDraftChanged();
  }

  Future<void> _openItemSheet(
    List<Map<String, dynamic>> catalog, {
    int? editIndex,
    Map<String, dynamic>? initialOverride,
  }) async {
    final draft = ref.read(purchaseDraftProvider);
    if (draft.supplierId == null || draft.supplierId!.isEmpty) return;
    final session = ref.read(sessionProvider);
    final initial = initialOverride ??
        (editIndex != null
            ? ref.read(purchaseDraftProvider).lines[editIndex].toLineMap()
            : null);
    // Ensure the sheet can resolve `default_kg_per_bag` for this line (list may omit the row).
    var catalogForSheet = List<Map<String, dynamic>>.from(catalog);
    final cid = initial?['catalog_item_id']?.toString();
    if (cid != null && cid.isNotEmpty) {
      final has = catalogForSheet.any((m) => m['id']?.toString() == cid);
      if (!has) {
        if (session != null) {
          try {
            final row = await ref.read(hexaApiProvider).getCatalogItem(
                  businessId: session.primaryBusiness.id,
                  itemId: cid,
                );
            if (row.isNotEmpty) {
              catalogForSheet = [Map<String, dynamic>.from(row), ...catalogForSheet];
            }
          } catch (_) {}
        }
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => AddItemEntryPage(
          catalog: catalogForSheet,
          initial: initial,
          isEdit: editIndex != null,
          navigateCatalogQuickAddItem: session == null || catalog.isEmpty
              ? null
              : () async {
                  final row = catalog.first;
                  final catId = row['category_id']?.toString();
                  final tid = row['type_id']?.toString();
                  if (catId == null ||
                      tid == null ||
                      catId.isEmpty ||
                      tid.isEmpty) {
                    return null;
                  }
                  final res = await ctx.push<Map<String, dynamic>?>(
                    '/catalog/category/$catId/type/$tid/add-item',
                  );
                  if (!ctx.mounted) return null;
                  if (res != null &&
                      (res['id']?.toString().trim().isNotEmpty ?? false)) {
                    ref.invalidate(catalogItemsListProvider);
                    try {
                      await ref.read(catalogItemsListProvider.future);
                    } catch (_) {}
                  }
                  return res;
                },
          onDefaultsResolved: session == null
              ? null
              : (d) {
                  final notifier = ref.read(purchaseDraftProvider.notifier);
                  final pdays = d['payment_days'];
                  if (pdays is num && pdays.toInt() >= 0) {
                    notifier.setPaymentDaysText('${pdays.toInt()}');
                  }
                  final brid = d['broker_id']?.toString().trim();
                  if (brid != null && brid.isNotEmpty) {
                    final brokers =
                        ref.read(brokersListProvider).valueOrNull ?? const [];
                    var bn = 'Broker';
                    for (final b in brokers) {
                      if (b['id']?.toString() == brid) {
                        bn = b['name']?.toString() ?? bn;
                        break;
                      }
                    }
                    notifier.setBroker(brid, bn, fromSupplier: false);
                  }
                  _syncControllersFromDraft();
                  if (mounted) setState(() {});
                },
          resolveCatalogItem: session == null
              ? null
              : (String catalogItemId) => ref.read(hexaApiProvider).getCatalogItem(
                    businessId: session.primaryBusiness.id,
                    itemId: catalogItemId,
                  ),
          resolveLastDefaults: session == null
              ? null
              : (String catalogItemId) {
                  final d = ref.read(purchaseDraftProvider);
                  return ref.read(hexaApiProvider).lastTradePurchaseDefaults(
                        businessId: session.primaryBusiness.id,
                        catalogItemId: catalogItemId,
                        supplierId: d.supplierId,
                        brokerId: d.brokerId,
                      );
                },
          onCommitted: (line) {
            final p = PurchaseLineDraft.fromLineMap(
              Map<String, dynamic>.from(line),
            );
            ref.read(purchaseDraftProvider.notifier).addOrReplaceLine(
                  p,
                  editIndex: editIndex,
                );
            setState(() {
              _inlineSaveError = null;
            });
            _onDraftChanged();
          },
        ),
      ),
    );
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _addItemFocus.requestFocus();
    });
  }

  void _removeLineAt(int i) {
    ref.read(purchaseDraftProvider.notifier).removeLineAt(i);
    setState(() {});
    _onDraftChanged();
  }

  bool _isEditMode() =>
      widget.editingId != null && widget.editingId!.isNotEmpty;

  Future<void> _confirmDiscardIfNeeded() async {
    if (_isEditMode() || !_formDirty) return;
    final a = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard draft?'),
        content: const Text('You have unsaved changes. Leave without saving?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (a == true) {
      await _clearDraftInPrefs();
      if (!mounted) return;
      if (context.canPop()) context.pop();
    }
  }

  void _scrollSupplierIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _supplierSectionKey.currentContext;
      if (c != null) {
        Scrollable.ensureVisible(c, alignment: 0.1, duration: Duration.zero);
      }
    });
  }

  void _scrollItemsIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _itemsSectionKey.currentContext;
      if (c != null) {
        Scrollable.ensureVisible(c, alignment: 0.1, duration: Duration.zero);
      }
    });
  }

  bool _isDuplicatePurchase409(DioException e) {
    if (e.response?.statusCode != 409) return false;
    final data = e.response?.data;
    if (data is! Map) return false;
    final detail = data['detail'];
    return detail is Map &&
        detail['code']?.toString() == 'DUPLICATE_PURCHASE_DETECTED';
  }

  Future<void> _validateAndSave() async {
    if (_isSaving) return;
    setState(() {
      _inlineSaveError = null;
      _supplierFieldError = null;
    });
    final v = ref.read(purchaseSaveValidationProvider);
    if (!v.isOk) {
      if (v.errorMessage != null) {
        final msg = v.errorMessage!.toLowerCase();
        final isSupplier = msg.contains('supplier');
        if (isSupplier) {
          setState(() {
            _supplierFieldError = v.errorMessage;
            _inlineSaveError = null;
          });
          _scrollSupplierIntoView();
        } else {
          setState(() {
            _inlineSaveError = v.errorMessage;
            _supplierFieldError = null;
          });
          _scrollItemsIntoView();
        }
      } else if (v.lineErrors.isNotEmpty) {
        final first = v.lineErrors.values.first;
        setState(() {
          _inlineSaveError = first;
          _supplierFieldError = null;
        });
        _scrollItemsIntoView();
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm purchase save?'),
        content: Text(
          _isEditMode()
              ? 'Save changes to this purchase?'
              : 'Saving will submit this purchase to your records. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    HapticFeedback.mediumImpact();
    await _savePurchaseAttempt(forceDuplicate: false);
  }

  Future<void> _savePurchaseAttempt({required bool forceDuplicate}) async {
    if (_isSaving) return;
    final session = ref.read(sessionProvider);
    if (session == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Not signed in'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    setState(() => _isSaving = true);
    final bid = session.primaryBusiness.id;
    final api = ref.read(hexaApiProvider);
    final body =
        ref.read(purchaseDraftProvider.notifier).buildTradePurchaseBody(
              forceDuplicate: forceDuplicate,
            );
    final isEdit = _isEditMode();

    try {
      final saved = isEdit
          ? await api.updateTradePurchase(
              businessId: bid,
              purchaseId: widget.editingId!,
              body: body,
            )
          : await api.createTradePurchase(
              businessId: bid,
              body: body,
            );
      invalidatePurchaseWorkspace(ref);
      ref.read(purchaseDraftProvider.notifier).reset();
      await _clearDraftInPrefs();
      if (mounted) {
        setState(() {
          _isSaving = false;
          _formDirty = false;
        });
      }
      final pid = saved['id']?.toString() ?? '';
      if (pid.isNotEmpty) {
        unawaited(LocalNotificationsService.instance
            .scheduleTradePurchaseDueAtNineAmIfNeeded(
          purchaseId: pid,
          dueDateIso: saved['due_date']?.toString(),
          humanId: saved['human_id']?.toString(),
        ));
        final hm = saved['has_missing_details'] == true ||
            saved['has_missing_details']?.toString().toLowerCase() == 'true';
        if (hm) {
          unawaited(LocalNotificationsService.instance
              .schedulePurchaseMissingDetailsReminder(
            purchaseId: pid,
            humanId: saved['human_id']?.toString(),
          ));
        } else {
          unawaited(LocalNotificationsService.instance
              .cancelPurchaseMissingDetailsReminder(pid));
        }
      }
      if (!mounted) return;
      final quick = ref.read(quickSavePurchaseProvider);
      if (quick) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Purchase updated' : 'Purchase saved'),
            backgroundColor: Colors.green[700],
          ),
        );
        if (context.canPop()) context.pop();
      } else {
        final where = await showPurchaseSavedSheet(
          context,
          ref,
          savedJson: saved,
          wasEdit: isEdit,
        );
        if (!mounted) return;
        if (where == 'edit_missing') {
          final id = saved['id']?.toString();
          if (id != null && id.isNotEmpty) {
            context.push('/purchase/edit/$id');
          } else if (context.canPop()) {
            context.pop();
          }
          return;
        }
        if (where == 'later_missing') {
          if (context.canPop()) context.pop();
          return;
        }
        if (where == 'detail') {
          final id = saved['id']?.toString();
          if (id != null && id.isNotEmpty) {
            context.go('/purchase/detail/$id');
          }
        } else {
          if (context.canPop()) context.pop();
        }
      }
    } on DioException catch (e) {
      if (!forceDuplicate && _isDuplicatePurchase409(e)) {
        if (mounted) {
          setState(() => _isSaving = false);
        }
        if (!mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Similar purchase already exists'),
            content: const Text(
              'A purchase that looks like this is already recorded for this date. Continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save anyway'),
              ),
            ],
          ),
        );
        if (proceed == true && mounted) {
          await _savePurchaseAttempt(forceDuplicate: true);
        }
        return;
      }
      if (mounted) {
        final hint = fastApiPurchaseScrollHint(e.response?.data);
        if (hint != null && hint.supplierField) {
          // stay on single editor screen
        }
        setState(() {
          _isSaving = false;
          _inlineSaveError = friendlyApiError(e);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _inlineSaveError = friendlyApiError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(catalogItemsListProvider, (_, next) {
      next.whenData((d) {
        _lastCatalogSnapshot = d
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false);
      });
    });
    ref.listen<(String?, String?)>(
      purchaseDraftProvider.select((d) => (d.supplierId, d.supplierName)),
      (prev, next) {
        if (!mounted) return;
        final (id, name) = next;
        if (id == null || id.isEmpty) {
          if (_supplierCtrl.text.isNotEmpty) _supplierCtrl.clear();
        } else if (name != null && name.isNotEmpty && _supplierCtrl.text != name) {
          _supplierCtrl.text = name;
        }
      },
    );
    ref.listen<(String?, String?)>(
      purchaseDraftProvider.select((d) => (d.brokerId, d.brokerName)),
      (prev, next) {
        if (!mounted) return;
        final (id, name) = next;
        if (id == null || id.isEmpty) {
          if (_brokerCtrl.text.isNotEmpty) _brokerCtrl.clear();
        } else if (name != null && name.isNotEmpty && _brokerCtrl.text != name) {
          _brokerCtrl.text = name;
        }
      },
    );
    ref.listen(suppliersListProvider, (prev, next) {
      next.whenData((d) => _lastGoodSuppliers = d);
    });
    ref.listen(
      purchaseDraftProvider.select((d) => d.supplierId),
      (prev, next) {
        if (next == null || next.isEmpty) {
          _lastAutoSupplierFromCatalogSig = null;
        }
      },
    );
    final isEdit = _isEditMode();
    return PopScope(
      canPop: isEdit || !_formDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _confirmDiscardIfNeeded();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(isEdit ? 'Edit purchase' : 'New purchase'),
          elevation: 0,
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            bottom: false,
            child: Builder(
              builder: (context) {
                if (_isBootstrapping) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (_editBootstrapError != null) {
                  final err = _editBootstrapError!;
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_off_rounded,
                              size: 48,
                              color: Colors.orange.shade800),
                          const SizedBox(height: 16),
                          Text(
                            err,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FilledButton(
                                onPressed: () => _bootstrap(),
                                child: const Text('Retry'),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton(
                                onPressed: () => context.pop(),
                                child: const Text('Go back'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final catalogAsync = ref.watch(catalogItemsListProvider);
                final catalog = catalogAsync.valueOrNull ??
                    _lastCatalogSnapshot ??
                    const <Map<String, dynamic>>[];
                final emptyCache = catalog.isEmpty;
                final showTopLoad =
                    catalogAsync.isLoading && emptyCache;
                final showCatalogErrorStrip =
                    catalogAsync.hasError && emptyCache;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showTopLoad)
                      const SizedBox(
                        height: 3,
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                    if (showCatalogErrorStrip)
                      Material(
                        color: Colors.orange.shade50,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Text(
                            'Catalog could not refresh. ${catalogAsync.error}',
                            style: TextStyle(
                                color: Colors.orange.shade900, fontSize: 12),
                          ),
                        ),
                      ),
                    Expanded(
                      child: _buildBody(catalog, isEdit),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        bottomNavigationBar: Builder(
          builder: (context) {
            if (_isBootstrapping || _editBootstrapError != null) {
              return const SizedBox.shrink();
            }
            final catalogAsync = ref.watch(catalogItemsListProvider);
            final catalog = catalogAsync.valueOrNull ??
                _lastCatalogSnapshot ??
                const <Map<String, dynamic>>[];
            return _buildPurchaseSaveBar(catalog, isEdit);
          },
        ),
      ),
    );
  }

  Widget _buildBody(List<Map<String, dynamic>> catalog, bool isEdit) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final scrollBottom = viewInsets + safeBottom;
    const bottomBarReserve = 80.0;
    final scrollBottomPad = scrollBottom + bottomBarReserve;

    Widget errorStrip() {
      if (_inlineSaveError == null) return const SizedBox.shrink();
      return Material(
        color: Colors.red[50],
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Text(
            _inlineSaveError!,
            style: TextStyle(color: Colors.red[900], fontSize: 12),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        errorStrip(),
        _buildFixedPurchaseHeader(catalog, isEdit),
        Expanded(
          child: SingleChildScrollView(
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(10, 6, 10, scrollBottomPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildItemsSection(catalog, isEdit),
                const SizedBox(height: 10),
                ExpansionTile(
                  initiallyExpanded: false,
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    'Terms',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 8),
                      child: _buildTermsFields(catalog, isEdit),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static const double _kFieldHeight = 48;

  InputDecoration _denseFieldDeco(String label,
      {String? hint, String? prefixText}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefixText,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: HexaColors.brandPrimary, width: 2),
      ),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _buildFixedPurchaseHeader(
      List<Map<String, dynamic>> catalog, bool isEdit) {
    final draft = ref.watch(purchaseDraftProvider);
    return Padding(
      key: _supplierSectionKey,
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isEdit && _loadedDerivedStatus != null) ...[
            Text(
              'Payment: $_loadedDerivedStatus · Bal ₹${(_loadedRemaining ?? 0).toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 6),
          ],
          SizedBox(
            height: _kFieldHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: draft.purchaseDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        ref
                            .read(purchaseDraftProvider.notifier)
                            .setPurchaseDate(date);
                        _onDraftChanged();
                        setState(() {});
                      }
                    },
                    child: InputDecorator(
                      decoration: _denseFieldDeco('Date'),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              size: 16, color: HexaColors.brandPrimary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              DateFormat('dd MMM yyyy').format(
                                  draft.purchaseDate ?? DateTime.now()),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InputDecorator(
                    decoration: _denseFieldDeco(
                      isEdit ? 'Purchase ID' : 'ID (preview)',
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        isEdit
                            ? (_editHumanId ?? '—')
                            : (_previewHumanId ?? 'Auto'),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: isEdit
                              ? Colors.black87
                              : HexaColors.brandPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text('Supplier *',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(height: 4),
          _buildSupplierSearch(catalog),
          if (_supplierFieldError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _supplierFieldError!,
                style: TextStyle(color: Colors.red[800], fontSize: 12),
              ),
            ),
          if (draft.supplierId != null && draft.supplierId!.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  ref.read(purchaseDraftProvider.notifier).clearSupplier();
                  _supplierCtrl.clear();
                  _syncControllersFromDraft();
                  setState(() {});
                  _onDraftChanged();
                },
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Change supplier',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          const SizedBox(height: 4),
          _buildBrokerBlock(),
        ],
      ),
    );
  }

  Widget _buildTermsFields(
      List<Map<String, dynamic>> _, bool __) {
    final draft = ref.watch(purchaseDraftProvider);
    if (draft.supplierId == null || draft.supplierId!.isEmpty) {
      return const Text(
        'Select a supplier first.',
        style: TextStyle(fontSize: 13, color: Colors.grey),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (draft.supplierName != null && draft.supplierName!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_fix_high,
                      size: 14, color: Color(0xFF0D9488)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Defaults from ${draft.supplierName} (editable)',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF0D9488),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        SizedBox(
          height: _kFieldHeight + 18,
          child: TextField(
            controller: _paymentDaysCtrl,
            keyboardType: TextInputType.number,
            decoration: _denseFieldDeco('Payment days'),
            onChanged: (s) {
              ref.read(purchaseDraftProvider.notifier).setPaymentDaysText(s);
              _onDraftChanged();
            },
          ),
        ),
        if (_paymentDaysCtrl.text.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            _duePreviewText(),
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF0D9488),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: _kFieldHeight + 18,
                child: TextField(
                  controller: _deliveredRateCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: _denseFieldDeco('Delivered rate'),
                  onChanged: (s) {
                    ref.read(purchaseDraftProvider.notifier).setDeliveredText(s);
                    _onDraftChanged();
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: _kFieldHeight + 18,
                child: TextField(
                  controller: _billtyRateCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: _denseFieldDeco('Billty rate'),
                  onChanged: (s) {
                    ref.read(purchaseDraftProvider.notifier).setBilltyText(s);
                    _onDraftChanged();
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: _kFieldHeight + 18,
                child: TextField(
                  controller: _freightCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: _denseFieldDeco('Freight', prefixText: '₹ '),
                  onChanged: (s) {
                    ref.read(purchaseDraftProvider.notifier).setFreightText(s);
                    _onDraftChanged();
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: _kFieldHeight + 18,
                child: InputDecorator(
                  decoration: _denseFieldDeco('Freight type'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _freightType,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(
                          value: 'separate',
                          child: Text('Separate'),
                        ),
                        DropdownMenuItem(
                          value: 'included',
                          child: Text('Included'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _freightType = v);
                        ref
                            .read(purchaseDraftProvider.notifier)
                            .setFreightType(v);
                        _onDraftChanged();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _kFieldHeight + 18,
          child: TextField(
            controller: _commissionCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: _denseFieldDeco('Broker commission %'),
            onChanged: (s) {
              ref.read(purchaseDraftProvider.notifier).setCommissionText(s);
              _onDraftChanged();
            },
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _kFieldHeight + 18,
          child: TextField(
            controller: _headerDiscCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration:
                _denseFieldDeco('Discount % (purchase)'),
            onChanged: (s) {
              ref
                  .read(purchaseDraftProvider.notifier)
                  .setHeaderDiscountFromText(s);
              _onDraftChanged();
            },
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _kFieldHeight + 26,
          child: TextField(
            controller: _invoiceCtrl,
            maxLines: 2,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: _denseFieldDeco('Memo / invoice ref'),
            onChanged: (s) {
              ref.read(purchaseDraftProvider.notifier).setInvoiceText(s);
              _onDraftChanged();
            },
          ),
        ),
      ],
    );
  }

  /// Non-blocking: for lines with catalog ids, show top-3 suppliers from [tradeSupplierBrokerMap].
  Widget _buildSupplierHistoryHint() {
    final session = ref.watch(sessionProvider);
    final draft = ref.watch(purchaseDraftProvider);
    final cids = draft.lines
        .map((l) => l.catalogItemId)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList()
      ..sort();
    final key = cids.join('|');
    if (session == null || key.isEmpty) {
      _historyHintKey = null;
      _historySupplierNamesFuture = null;
      return const SizedBox.shrink();
    }
    if (_historyHintKey != key) {
      _historyHintKey = key;
      _historySupplierNamesFuture = _fetchSupplierHistoryHintsForCatalogs(
        session.primaryBusiness.id,
        cids.toSet(),
      );
    }
    return FutureBuilder<List<String>>(
      future: _historySupplierNamesFuture,
      builder: (context, snap) {
        if (snap.hasData && (snap.data?.isNotEmpty ?? false)) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'From your trade history: ${snap.data!.join(" · ")}',
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildSupplierSearch(List<Map<String, dynamic>> catalog) {
    final av = ref.watch(suppliersListProvider);
    return av.when(
      data: (list) {
        final full = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        final filtered = _filterSuppliersByCatalogLineDefaults(full, catalog);
        final sig =
            '${ref.read(purchaseDraftProvider).lines.map((l) => l.catalogItemId ?? "").join(",")}|${filtered.length}|${full.length}';
        if (filtered.length == 1 &&
            full.isNotEmpty &&
            (ref.read(purchaseDraftProvider).supplierId == null ||
                ref.read(purchaseDraftProvider).supplierId!.isEmpty)) {
          if (_lastAutoSupplierFromCatalogSig != sig) {
            _lastAutoSupplierFromCatalogSig = sig;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final d = ref.read(purchaseDraftProvider);
              if (d.supplierId != null && d.supplierId!.isNotEmpty) return;
              if (filtered.length != 1) return;
              final row = filtered.first;
              if (_supplierRowId(row).isEmpty) return;
              _applySupplierSelection(
                full,
                InlineSearchItem(
                  id: _supplierRowId(row),
                  label: _supplierMapLabel(row),
                  subtitle: _supplierSearchSubtitle(row),
                ),
              );
            });
          }
        }
        return _supplierColumn(filtered, full, narrowed: filtered.length < full.length);
      },
      error: (_, __) {
        if (_lastGoodSuppliers != null) {
          final full = _lastGoodSuppliers!
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          return _supplierColumn(
            _filterSuppliersByCatalogLineDefaults(full, catalog),
            full,
            narrowed: false,
          );
        }
        return const Text('Could not load suppliers');
      },
      loading: () {
        if (_lastGoodSuppliers != null) {
          final full = _lastGoodSuppliers!
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          return _supplierColumn(
            _filterSuppliersByCatalogLineDefaults(full, catalog),
            full,
            narrowed: false,
          );
        }
        return const LinearProgressIndicator();
      },
    );
  }

  Widget _supplierColumn(
    List<Map<String, dynamic>> list,
    List<Map<String, dynamic>> lookupList, {
    bool narrowed = false,
  }) {
    if (list.isEmpty) {
      return const Text(
        'No suppliers in this workspace yet — add one under Suppliers or run bootstrap.',
        style: TextStyle(fontSize: 12),
      );
    }
    final sorted = _sortSuppliersByPurchaseRecency(list);
    final items = <InlineSearchItem>[
      for (final m in sorted)
        if (_supplierRowId(m).isNotEmpty)
          InlineSearchItem(
            id: _supplierRowId(m),
            label: _supplierMapLabel(m),
            subtitle: _supplierSearchSubtitle(m),
          ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (narrowed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Only suppliers saved as defaults for the catalog line(s) you added.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: InlineSearchField(
                key: const ValueKey('purchase_supplier_search'),
                controller: _supplierCtrl,
                placeholder: 'Type at least 1 letter, then pick from the list…',
                prefixIcon: const Icon(Icons.business),
                items: items,
                onSelected: (it) {
                  if (it.id.isEmpty) return;
                  _applySupplierSelection(lookupList, it);
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Add new supplier',
              icon: const Icon(Icons.add_circle_outline, color: Color(0xFF17A8A7)),
              onPressed: () => _openQuickSupplierCreate(lookupList),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBrokerBlock() {
    final draft = ref.watch(purchaseDraftProvider);
    final supplierRow = draft.supplierId != null && draft.supplierId!.isNotEmpty
        ? _supplierRowById(draft.supplierId!)
        : null;
    final defaultBid = supplierRow?['broker_id']?.toString();
    final hasDefault =
        defaultBid != null && defaultBid.isNotEmpty && (draft.brokerId == null || draft.brokerId!.isEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Broker (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        if (hasDefault)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: OutlinedButton.icon(
              onPressed: _applyBrokerFromSupplierRow,
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Use supplier’s default broker'),
            ),
          ),
        if (draft.brokerId != null && draft.brokerId!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    (draft.brokerName != null && draft.brokerName!.trim().isNotEmpty)
                        ? draft.brokerName!.trim()
                        : 'Broker',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    ref.read(purchaseDraftProvider.notifier).setBroker(null, null);
                    _brokerCtrl.clear();
                    setState(() {});
                    _onDraftChanged();
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
        _buildBrokerSearch(),
      ],
    );
  }

  Widget _buildBrokerSearch() {
    final av = ref.watch(brokersListProvider);
    return av.when(
      data: (list) => _brokerColumn(list),
      error: (_, __) => const Text('Could not load brokers'),
      loading: () => const LinearProgressIndicator(),
    );
  }

  Widget _brokerColumn(List<Map<String, dynamic>> list) {
    if (list.isEmpty) {
      return const Text(
        'No brokers yet — add one under Brokers or leave blank.',
        style: TextStyle(fontSize: 12),
      );
    }
    final items = <InlineSearchItem>[
      for (final m in list)
        if (_brokerRowId(m).isNotEmpty)
          InlineSearchItem(
            id: _brokerRowId(m),
            label: _brokerMapLabel(m),
          ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: InlineSearchField(
            key: const ValueKey('purchase_broker_search'),
            controller: _brokerCtrl,
            placeholder: 'Search broker (optional)…',
            prefixIcon: const Icon(Icons.person_search_outlined),
            items: items,
            onSelected: (it) {
              if (it.id.isEmpty) return;
              _applyBrokerSelection(list, it);
            },
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Add new broker',
          icon: const Icon(Icons.add_circle_outline, color: Color(0xFF17A8A7)),
          onPressed: () => _openQuickBrokerCreate(list),
        ),
      ],
    );
  }

  Widget _buildItemsSection(
    List<Map<String, dynamic>> catalog,
    bool isEdit,
  ) {
    final supplierId = ref.watch(purchaseDraftProvider.select((d) => d.supplierId));
    final lines = ref.watch(purchaseDraftProvider.select((d) => d.lines));
    return Column(
      key: _itemsSectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Items',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: supplierId == null || supplierId.isEmpty
                  ? null
                  : () => _openItemSheet(catalog),
              style: TextButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Item'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _buildSupplierHistoryHint(),
        if (lines.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              supplierId == null || supplierId.isEmpty
                  ? 'Select a supplier first.'
                  : 'No items yet.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          )
        else
          ...List.generate(lines.length, (i) {
            final it = lines[i];
            final line = TradeCalcLine(
              qty: it.qty,
              landingCost: it.landingCost,
              kgPerUnit: it.kgPerUnit,
              landingCostPerKg: it.landingCostPerKg,
              taxPercent: it.taxPercent,
              discountPercent: it.lineDiscountPercent,
            );
            final total = lineMoney(line);
            final kpu = it.kgPerUnit;
            final lck = it.landingCostPerKg;
            final rateUnit = (kpu != null && lck != null && kpu > 0 && lck > 0)
                ? (kpu * lck)
                : it.landingCost;
            final qtyStr = StrictDecimal.fromObject(it.qty).format(3, trim: true);
            final lineText =
                '$qtyStr × ₹${rateUnit.toStringAsFixed(2)} = ₹${total.toStringAsFixed(2)} · ${it.unit.trim()}';

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openItemSheet(catalog, editIndex: i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                it.itemName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                lineText,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[800],
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Edit',
                          iconSize: 20,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minHeight: _kFieldHeight,
                              minWidth: _kFieldHeight),
                          icon: const Icon(Icons.edit_outlined,
                              color: HexaColors.brandPrimary),
                          onPressed: () =>
                              _openItemSheet(catalog, editIndex: i),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          iconSize: 20,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minHeight: _kFieldHeight,
                              minWidth: _kFieldHeight),
                          icon: Icon(Icons.delete_outline_rounded,
                              color: Colors.red[700]),
                          onPressed: () => _removeLineAt(i),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildPurchaseSaveBar(
      List<Map<String, dynamic>> _, bool isEdit) {
    final saveVal = ref.watch(purchaseSaveValidationProvider);
    final canSave = saveVal.isOk;
    return SafeArea(
      child: Material(
        elevation: 6,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!canSave)
              Container(
                color: Colors.red.shade50,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(
                  saveVal.errorMessage ??
                      (saveVal.lineErrors.isNotEmpty
                          ? saveVal.lineErrors.values.first
                          : 'Supplier and at least one valid line required.'),
                  style: TextStyle(color: Colors.red[800], fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: SizedBox(
                height: 48,
                width: double.infinity,
                child: FilledButton(
                  onPressed: (!canSave || _isSaving) ? null : _validateAndSave,
                  child: _isSaving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save Purchase',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
