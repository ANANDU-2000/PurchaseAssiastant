import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/fastapi_error.dart';
import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/business_aggregates_invalidation.dart'
    show invalidatePurchaseWorkspace, invalidateWorkspaceSeedData;
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/prefs_provider.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/services/offline_store.dart';
import '../../../core/notifications/local_notifications_service.dart';
import '../../purchase/domain/purchase_draft.dart';
import '../../purchase/state/purchase_draft_provider.dart';

import '../../../shared/widgets/keyboard_safe_form_viewport.dart';
import '../../../shared/widgets/inline_search_field.dart';
import 'wizard/purchase_items_step.dart';
import 'wizard/purchase_party_step.dart';
import 'wizard/purchase_summary_step.dart';
import 'wizard/purchase_terms_step.dart';
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

  Timer? _draftDebounce;

  /// Latest [purchase_date] per supplier from recent trade list (for autocomplete sort).
  Map<String, DateTime> _supplierLastPurchaseById = {};

  /// Ignore stale async work when the user picks another supplier before requests finish.
  int _supplierApplySeq = 0;

  /// 0 party → 1 items → 2 terms → 3 summary (no dots UI).
  int _wizStep = 0;

  final _supplierCtrl = TextEditingController();
  final _brokerCtrl = TextEditingController();
  final _partySupplierFocus = FocusNode();
  final _partyBrokerFocus = FocusNode();
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
        ref
            .read(purchaseDraftProvider.notifier)
            .replaceDraft(widget.initialDraft!);
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
    _deliveredRateCtrl.text =
        d.deliveredRate != null ? d.deliveredRate!.toStringAsFixed(2) : '';
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
          const SnackBar(content: Text('Restored your unsaved purchase draft')),
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

  /// Immediate save for party-step footer (still debounces on normal edits via [_onDraftChanged]).
  void _saveDraftNow() {
    _draftDebounce?.cancel();
    _flushDraftToPrefs();
    if (!mounted || widget.editingId != null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Draft saved')),
    );
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
    _supplierCtrl.dispose();
    _brokerCtrl.dispose();
    _paymentDaysCtrl.dispose();
    _headerDiscCtrl.dispose();
    _commissionCtrl.dispose();
    _deliveredRateCtrl.dispose();
    _billtyRateCtrl.dispose();
    _freightCtrl.dispose();
    _invoiceCtrl.dispose();
    _partySupplierFocus.dispose();
    _partyBrokerFocus.dispose();
    super.dispose();
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
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
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
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
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

  String _apiDateOnly(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
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
      ..sort((a, b) =>
          (b.value['deals'] as int).compareTo(a.value['deals'] as int));
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
    final filtered =
        allSuppliers.where((m) => allow.contains(_supplierRowId(m))).toList();
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

    // Commit draft immediately so a tap cannot be wiped by overlapping async / seq churn.
    final commitRow = Map<String, dynamic>.from(row);
    if (mounted && seq == _supplierApplySeq) {
      ref
          .read(purchaseDraftProvider.notifier)
          .applySupplierSelection(commitRow, it.id, it.label);
      _syncControllersFromDraft();
      setState(() {
        _supplierFieldError = null;
        _inlineSaveError = null;
      });
      _onDraftChanged();
    }

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
    // Re-apply after possible fresh master row fetch (still same selection).
    ref
        .read(purchaseDraftProvider.notifier)
        .applySupplierSelection(supplierRow, it.id, it.label);
    if (session != null) {
      try {
        final autofill =
            await ref.read(hexaApiProvider).tradeLastSupplierAutofill(
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
              catalogForSheet = [
                Map<String, dynamic>.from(row),
                ...catalogForSheet
              ];
            }
          } catch (_) {}
        }
      }
    }
    if (!mounted) return;
    final addMore = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
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
              : (String catalogItemId) =>
                  ref.read(hexaApiProvider).getCatalogItem(
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
    if (addMore == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final d = ref.read(purchaseDraftProvider);
        if (d.supplierId == null || d.supplierId!.isEmpty) return;
        unawaited(_openItemSheet(catalog));
      });
    }
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
            _wizStep = 0;
          });
        } else {
          setState(() {
            _inlineSaveError = v.errorMessage;
            _supplierFieldError = null;
            _wizStep = 1;
          });
        }
      } else if (v.lineErrors.isNotEmpty) {
        final first = v.lineErrors.values.first;
        setState(() {
          _inlineSaveError = first;
          _supplierFieldError = null;
          _wizStep = 1;
        });
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

  Future<void> _wizBack() async {
    FocusScope.of(context).unfocus();
    if (_wizStep > 0) {
      setState(() => _wizStep -= 1);
      return;
    }
    if (!mounted) return;
    if (_isEditMode()) {
      if (context.canPop()) context.pop();
      return;
    }
    if (!_formDirty) {
      if (context.canPop()) context.pop();
      return;
    }
    await _confirmDiscardIfNeeded();
  }

  void _partyAdvanceIfValid() {
    final g = ref.read(purchaseStepGatesProvider);
    setState(() => _inlineSaveError = null);
    if (!g.from0) {
      setState(() {
        _supplierFieldError = 'Select a supplier.';
      });
      return;
    }
    setState(() {
      _supplierFieldError = null;
      _wizStep = 1;
    });
    FocusScope.of(context).unfocus();
  }

  void _wizNext() {
    if (_wizStep != 0) {
      FocusScope.of(context).unfocus();
    }
    final g = ref.read(purchaseStepGatesProvider);
    setState(() => _inlineSaveError = null);
    if (_wizStep == 0) {
      _partyAdvanceIfValid();
      return;
    }
    if (_wizStep == 1) {
      if (!g.from1) {
        final v = ref.read(purchaseSaveValidationProvider);
        setState(() {
          _inlineSaveError = v.errorMessage ??
              (v.lineErrors.isNotEmpty ? v.lineErrors.values.first : null) ??
              'Add at least one valid item.';
          _supplierFieldError = null;
        });
        return;
      }
      setState(() => _wizStep = 2);
      return;
    }
    if (_wizStep == 2) {
      if (!g.from2) {
        final v = ref.read(purchaseSaveValidationProvider);
        setState(() {
          _inlineSaveError = v.errorMessage ??
              (v.lineErrors.isNotEmpty ? v.lineErrors.values.first : null);
        });
        return;
      }
      setState(() => _wizStep = 3);
    }
  }

  Widget _wizBody(List<Map<String, dynamic>> catalog, bool isEdit) {
    final session = ref.read(sessionProvider);
    final bid = session?.primaryBusiness.id;

    Widget stepSlot() {
      switch (_wizStep) {
        case 0:
          return PurchasePartyStep(
            isEdit: isEdit,
            loadedDerivedStatus: _loadedDerivedStatus,
            loadedRemaining: _loadedRemaining,
            previewHumanId: _previewHumanId,
            editHumanId: _editHumanId,
            supplierCtrl: _supplierCtrl,
            brokerCtrl: _brokerCtrl,
            supplierFocusNode: _partySupplierFocus,
            brokerFocusNode: _partyBrokerFocus,
            onProceedFromParty: _partyAdvanceIfValid,
            supplierFieldError: _supplierFieldError,
            catalog: catalog,
            lastGoodSuppliers: _lastGoodSuppliers,
            lastAutoSupplierFromCatalogSig: _lastAutoSupplierFromCatalogSig,
            onLastAutoSupplierFromCatalogSigChanged: (sig) {
              setState(() => _lastAutoSupplierFromCatalogSig = sig);
            },
            onDraftChanged: _onDraftChanged,
            supplierSubtitleFor: _supplierSearchSubtitle,
            supplierRowId: _supplierRowId,
            supplierMapLabel: _supplierMapLabel,
            sortSuppliers: _sortSuppliersByPurchaseRecency,
            filterSuppliersByCatalog: _filterSuppliersByCatalogLineDefaults,
            onSupplierSelectedSync: _applySupplierSelection,
            openQuickSupplierCreate: _openQuickSupplierCreate,
            onSupplierClear: () {
              ref.read(purchaseDraftProvider.notifier).clearSupplier();
              _supplierCtrl.clear();
              _syncControllersFromDraft();
              _onDraftChanged();
              setState(() {});
            },
            applyBrokerSelection: _applyBrokerSelection,
            openQuickBrokerCreate: _openQuickBrokerCreate,
            brokerRowId: _brokerRowId,
            brokerMapLabel: _brokerMapLabel,
          );
        case 1:
          return PurchaseItemsStep(
            onOpenItem: ({editIndex, initialOverride}) => _openItemSheet(
                catalog,
                editIndex: editIndex,
                initialOverride: initialOverride),
            fetchSupplierHistoryHints: _fetchSupplierHistoryHintsForCatalogs,
            hexaBusinessIdOrNull: bid,
          );
        case 2:
          return PurchaseTermsStep(
            paymentDaysCtrl: _paymentDaysCtrl,
            deliveredRateCtrl: _deliveredRateCtrl,
            billtyRateCtrl: _billtyRateCtrl,
            freightCtrl: _freightCtrl,
            commissionCtrl: _commissionCtrl,
            headerDiscCtrl: _headerDiscCtrl,
            memoCtrl: _invoiceCtrl,
            freightType: _freightType,
            onFreightTypeChanged: (v) {
              setState(() => _freightType = v);
              ref.read(purchaseDraftProvider.notifier).setFreightType(v);
              _onDraftChanged();
            },
            onDraftChanged: _onDraftChanged,
          );
        case 3:
          return const PurchaseSummaryStep();
        default:
          return const PurchaseSummaryStep();
      }
    }

    return Builder(
      builder: (context) {
        final step = stepSlot();
        if (_wizStep == 0) {
          final bottomPad = MediaQuery.paddingOf(context).bottom + 12;
          final surfaceColor = Theme.of(context).colorScheme.surface;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(12, 8, 12, bottomPad),
                  child: step,
                ),
              ),
              Material(
                elevation: 4,
                color: surfaceColor,
                child: SafeArea(
                  top: false,
                  child: _wizardFooterChrome(catalog, isEdit),
                ),
              ),
            ],
          );
        }

        return LayoutBuilder(
          builder: (context, cts) {
            final minFields = math.max(220.0, cts.maxHeight - 280);
            final surfaceColor = Theme.of(context).colorScheme.surface;
            return KeyboardSafeFormViewport(
              horizontalPadding: 12,
              minFieldsHeight: cts.hasBoundedHeight ? minFields : 220,
              fields: step,
              footer: Material(
                elevation: 8,
                color: surfaceColor,
                child: _wizardFooterChrome(catalog, isEdit),
              ),
            );
          },
        );
      },
    );
  }

  Widget _wizardFooterChrome(List<Map<String, dynamic>> catalog, bool isEdit) {
    if (_wizStep == 0 && !isEdit && (widget.editingId == null)) {
      final hintStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
            height: 1.25,
          );
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton(
                onPressed: _saveDraftNow,
                child: const Text(
                  'Save draft',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Draft stays on this device until you tap Save draft or finish the wizard. Saving the purchase syncs to the server.',
              textAlign: TextAlign.center,
              style: hintStyle,
            ),
          ],
        ),
      );
    }

    // Edit mode step 0: no separate draft row (same parity as legacy).
    if (_wizStep == 0) {
      return const SizedBox.shrink();
    }
    final gates = ref.watch(purchaseStepGatesProvider);
    final saveVal = ref.watch(purchaseSaveValidationProvider);
    final canAddItem = gates.from0 && !_isSaving;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_inlineSaveError != null &&
            (_wizStep == 1 ||
                _wizStep == 2 ||
                (_wizStep == 3 && !saveVal.isOk)))
          Material(
            color: Colors.red[50],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                _inlineSaveError!,
                style: TextStyle(color: Colors.red[900], fontSize: 12),
              ),
            ),
          ),
        if (_wizStep == 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SizedBox(
              height: 48,
              width: double.infinity,
              child: FilledButton(
                onPressed: canAddItem ? () => _openItemSheet(catalog) : null,
                child: const Text(
                  'Add item',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        if (_wizStep == 3)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!saveVal.isOk)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      saveVal.errorMessage ??
                          (saveVal.lineErrors.isNotEmpty
                              ? saveVal.lineErrors.values.first
                              : ''),
                      style: TextStyle(color: Colors.red[800], fontSize: 12),
                    ),
                  ),
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        (!saveVal.isOk || _isSaving) ? null : _validateAndSave,
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
                            'Save purchase',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: _wizStep == 3
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _isSaving ? null : () => _wizBack(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                  ),
                )
              : Row(
                  children: [
                    if (_wizStep > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSaving ? null : () => _wizBack(),
                          child: const Text('Back'),
                        ),
                      ),
                    if (_wizStep > 0) const SizedBox(width: 10),
                    Expanded(
                      flex: _wizStep > 0 ? 2 : 1,
                      child: FilledButton(
                        onPressed: _isSaving ? null : _wizNext,
                        child: const Text(
                          'Continue',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
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
        } else if (name != null &&
            name.isNotEmpty &&
            _supplierCtrl.text != name) {
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
        } else if (name != null &&
            name.isNotEmpty &&
            _brokerCtrl.text != name) {
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
    final appBarTitle = isEdit
        ? 'Edit purchase'
        : (_wizStep == 0 ? 'New Purchase' : 'New purchase');
    Widget purchaseWizardSafeBody() {
      return SafeArea(
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
                          size: 48, color: Colors.orange.shade800),
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
            final showTopLoad = catalogAsync.isLoading && emptyCache;
            final showCatalogErrorStrip = catalogAsync.hasError && emptyCache;

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
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _wizBody(catalog, isEdit),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    return PopScope(
      canPop: isEdit || !_formDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_wizStep > 0) {
          FocusScope.of(context).unfocus();
          setState(() => _wizStep -= 1);
          return;
        }
        await _confirmDiscardIfNeeded();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(appBarTitle),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _isSaving ? null : () => _wizBack(),
          ),
        ),
        body: _wizStep == 0
            ? purchaseWizardSafeBody()
            : GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusScope.of(context).unfocus(),
                child: purchaseWizardSafeBody(),
              ),
      ),
    );
  }
}
