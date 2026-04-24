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
import '../../../core/calc_engine.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/business_aggregates_invalidation.dart'
    show invalidateBusinessAggregates, invalidateWorkspaceSeedData;
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/prefs_provider.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/notifications/local_notifications_service.dart';
import '../../purchase/domain/purchase_draft.dart';
import '../../purchase/state/purchase_draft_provider.dart';
import '../../../shared/widgets/inline_search_field.dart';
import 'widgets/purchase_item_entry_sheet.dart';
import 'widgets/purchase_saved_sheet.dart';

class PurchaseEntryWizardV2 extends ConsumerStatefulWidget {
  const PurchaseEntryWizardV2({
    super.key,
    this.editingId,
    this.initialCatalogItemId,
  });

  final String? editingId;
  final String? initialCatalogItemId;

  @override
  ConsumerState<PurchaseEntryWizardV2> createState() =>
      _PurchaseEntryWizardV2State();
}

class _PurchaseEntryWizardV2State extends ConsumerState<PurchaseEntryWizardV2>
    with SingleTickerProviderStateMixin {
  int _currentStep = 0;
  bool _isBootstrapping = false;
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
  Timer? _draftDebounce;

  final _supplierSectionKey = GlobalKey();
  final _itemsSectionKey = GlobalKey();
  final _addItemFocus = FocusNode();

  final _supplierCtrl = TextEditingController();
  final _brokerCtrl = TextEditingController();
  final _invoiceCtrl = TextEditingController();
  final _paymentDaysCtrl = TextEditingController();
  final _headerDiscCtrl = TextEditingController();
  final _commissionCtrl = TextEditingController();
  final _deliveredRateCtrl = TextEditingController();
  final _billtyRateCtrl = TextEditingController();
  final _freightCtrl = TextEditingController();
  String _freightType = 'separate';

  /// Zero-duration open for the item line sheet (no slide lag).
  late final AnimationController _itemSheetOpenAnim =
      AnimationController(vsync: this, duration: Duration.zero);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final notifier = ref.read(purchaseDraftProvider.notifier);
    if (widget.editingId != null && widget.editingId!.isNotEmpty) {
      if (!mounted) return;
      setState(() => _isBootstrapping = true);
      final raw = await notifier.loadFromEdit(widget.editingId!);
      if (raw != null) {
        _editHumanId = raw['human_id']?.toString();
        _loadedDerivedStatus = raw['derived_status']?.toString();
        _loadedRemaining = (raw['remaining'] as num?)?.toDouble();
      }
      if (!mounted) return;
      _syncControllersFromDraft();
      setState(() => _isBootstrapping = false);
    } else {
      if (!mounted) return;
      notifier.reset();
      await _maybeRestoreDraft();
      if (!mounted) return;
      _syncControllersFromDraft();
    }
    if (!mounted) return;
    await _prefetchNextHumanId();
    if (!mounted) return;
    await _openCatalogLinePrefillIfNeeded();
    if (!mounted) return;
    await _ensureCatalogSeedIfEmpty();
  }

  void _syncControllersFromDraft() {
    final d = ref.read(purchaseDraftProvider);
    _freightType = d.freightType;
    _supplierCtrl.text = d.supplierName ?? '';
    _brokerCtrl.text = d.brokerName ?? '';
    _invoiceCtrl.text = d.invoiceNumber ?? '';
    _paymentDaysCtrl.text = d.paymentDays != null ? '${d.paymentDays}' : '';
    _headerDiscCtrl.text = d.headerDiscountPercent != null
        ? d.headerDiscountPercent.toString()
        : '';
    _commissionCtrl.text = d.commissionPercent != null
        ? d.commissionPercent.toString()
        : '';
    _deliveredRateCtrl.text = d.deliveredRate != null
        ? d.deliveredRate.toString()
        : '';
    _billtyRateCtrl.text = d.billtyRate != null ? d.billtyRate.toString() : '';
    _freightCtrl.text =
        d.freightAmount != null ? d.freightAmount.toString() : '';
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
    if (k == null) return;
    final p = ref.read(sharedPreferencesProvider);
    final s = p.getString(k);
    if (s == null || s.isEmpty) return;
    try {
      final o = jsonDecode(s);
      if (o is! Map) return;
      ref.read(purchaseDraftProvider.notifier).applyFromPrefsMap(
            Map<String, dynamic>.from(o),
          );
      if (!mounted) return;
      _syncControllersFromDraft();
      setState(() => _formDirty = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Restored your unsaved purchase draft')),
        );
      }
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
    if (k == null) return;
    final p = ref.read(sharedPreferencesProvider);
    final json =
        jsonEncode(ref.read(purchaseDraftProvider.notifier).toPrefsMap());
    unawaited(p.setString(k, json));
  }

  Future<void> _clearDraftInPrefs() async {
    final k = _draftPrefsKey();
    if (k == null) return;
    final p = ref.read(sharedPreferencesProvider);
    await p.remove(k);
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    if (widget.editingId == null || widget.editingId!.isEmpty) {
      final s = ref.read(sessionProvider);
      if (s != null) {
        final k = '${_draftKeyV1}_${s.primaryBusiness.id}';
        final p = ref.read(sharedPreferencesProvider);
        final json =
            jsonEncode(ref.read(purchaseDraftProvider.notifier).toPrefsMap());
        unawaited(p.setString(k, json));
      }
    }
    _addItemFocus.dispose();
    _supplierCtrl.dispose();
    _brokerCtrl.dispose();
    _invoiceCtrl.dispose();
    _paymentDaysCtrl.dispose();
    _headerDiscCtrl.dispose();
    _commissionCtrl.dispose();
    _deliveredRateCtrl.dispose();
    _billtyRateCtrl.dispose();
    _freightCtrl.dispose();
    _itemSheetOpenAnim.dispose();
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

  void _applySupplierSelection(
    List<Map<String, dynamic>> list,
    InlineSearchItem it,
  ) {
    if (it.id.isEmpty) return;
    final want = it.id.trim().toLowerCase();
    Map<String, dynamic>? row;
    for (final m in list) {
      if (_supplierRowId(m).toLowerCase() == want) {
        row = m;
        break;
      }
    }
    // Still commit id+label so Next / gates work even if the row shape drifts
    // (e.g. stale list vs. suggestion) or the API uses an alternate id key.
    row ??= <String, dynamic>{'id': it.id, 'name': it.label};
    ref
        .read(purchaseDraftProvider.notifier)
        .setSupplierFromMap(row, it.id, it.label);
    // The `ref.listen` in build() reflects supplierName → _supplierCtrl.
    // Terms/delivered/billty/etc. come from the row.
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
        final session = ref.read(sessionProvider);
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
    final mq = MediaQuery.of(context);
    final sheetMax = math.min(
      mq.size.height * 0.88,
      mq.size.height - mq.padding.top - 16,
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      useSafeArea: true,
      transitionAnimationController: _itemSheetOpenAnim,
      // Use most of the viewport so compact line sheet doesn’t feel clipped (old 720 cap caused extra scroll).
      constraints: BoxConstraints(maxHeight: math.max(320.0, sheetMax)),
      builder: (ctx) {
        final viewBottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: viewBottom),
          child: PurchaseItemEntrySheet(
            catalog: catalogForSheet,
            initial: initial,
            isEdit: editIndex != null,
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
        );
      },
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

  void _onContinue() {
    final g = ref.read(purchaseStepGatesProvider);
    if (_currentStep == 0) {
      if (!g.from0) {
        setState(() {
          _supplierFieldError =
              'Pick a supplier from the suggestions list (typing alone is not enough).';
          _inlineSaveError = null;
        });
        _scrollSupplierIntoView();
        return;
      }
      setState(() {
        _supplierFieldError = null;
        _inlineSaveError = null;
        _currentStep = 1;
      });
      HapticFeedback.selectionClick();
      return;
    }
    if (_currentStep == 1) {
      if (!g.from1) return;
      setState(() {
        _inlineSaveError = null;
        _currentStep = 2;
      });
      HapticFeedback.selectionClick();
      return;
    }
    if (_currentStep == 2) {
      if (!g.from2) {
        setState(() {
          _inlineSaveError =
              'Add at least one item with name, quantity > 0, and landing cost > 0.';
        });
        _scrollItemsIntoView();
        return;
      }
      setState(() {
        _inlineSaveError = null;
        _currentStep = 3;
      });
      HapticFeedback.selectionClick();
    }
  }

  void _onBack() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      HapticFeedback.selectionClick();
    }
  }

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

  Future<void> _validateAndSave() async {
    if (_isSaving) return;
    setState(() {
      _inlineSaveError = null;
      _supplierFieldError = null;
    });
    final v = ref.read(purchaseSaveValidationProvider);
    if (v.errorMessage != null) {
      final msg = v.errorMessage!.toLowerCase();
      final isSupplier = msg.contains('supplier');
      if (isSupplier) {
        setState(() {
          _supplierFieldError = v.errorMessage;
          _currentStep = 0;
        });
        _scrollSupplierIntoView();
      } else {
        // All other save checks are about lines / items (empty list or bad line).
        setState(() {
          _inlineSaveError = v.errorMessage;
          _currentStep = 2;
        });
        _scrollItemsIntoView();
      }
      return;
    }
    HapticFeedback.mediumImpact();
    await _savePurchase();
  }

  Future<void> _savePurchase() async {
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
        ref.read(purchaseDraftProvider.notifier).buildTradePurchaseBody();
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
      invalidateTradePurchaseCaches(ref);
      ref.invalidate(suppliersListProvider);
      invalidateBusinessAggregates(ref);
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
        // Fire-and-forget so navigation to the saved sheet / detail never
        // waits on local-notification I/O (plugin round-trips can be slow
        // on first boot and are not user-facing).
        unawaited(LocalNotificationsService.instance
            .scheduleTradePurchaseDueAtNineAmIfNeeded(
          purchaseId: pid,
          dueDateIso: saved['due_date']?.toString(),
          humanId: saved['human_id']?.toString(),
        ));
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
      if (mounted) {
        final hint = fastApiPurchaseScrollHint(e.response?.data);
        if (hint != null && hint.supplierField) {
          setState(() => _currentStep = 0);
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
    final isEdit = _isEditMode();
    return PopScope(
      canPop: isEdit || !_formDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _confirmDiscardIfNeeded();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEdit ? 'Edit purchase' : 'New purchase'),
          elevation: 0,
        ),
        body: _isBootstrapping
            ? const Center(child: CircularProgressIndicator())
            : ref.watch(catalogItemsListProvider).when(
                  loading: () => const Center(child: LinearProgressIndicator()),
                  error: (_, __) =>
                      const Center(child: Text('Could not load catalog')),
                  data: (catalog) => _buildBody(catalog, isEdit),
                ),
      ),
    );
  }

  static const _stageLabels = ['Supplier', 'Terms', 'Items', 'Summary'];

  Widget _buildStageHeader() {
    return Semantics(
      label: 'Purchase steps',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          children: List.generate(_stageLabels.length, (i) {
            final done = _currentStep > i;
            final active = _currentStep == i;
            final canJump = done || active;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: canJump
                      ? () {
                          setState(() => _currentStep = i);
                          HapticFeedback.selectionClick();
                        }
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: active
                              ? HexaColors.brandPrimary
                              : done
                                  ? const Color(0xFF0D9488)
                                  : Colors.grey[300],
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: active || done ? Colors.white : Colors.grey[700],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _stageLabels[i],
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                            color: active ? Colors.black87 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildActiveStepPanel(List<Map<String, dynamic>> catalog, bool isEdit) {
    final Widget child;
    switch (_currentStep) {
      case 0:
        child = _buildStepSupplier(catalog, isEdit);
        break;
      case 1:
        child = _buildStepTerms(catalog, isEdit);
        break;
      case 2:
        child = _buildStepItems(catalog, isEdit);
        break;
      default:
        child = _buildStepSummary(catalog, isEdit);
    }
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[300]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }

  Widget _buildBody(List<Map<String, dynamic>> catalog, bool isEdit) {
    return Column(
      children: [
        if (_inlineSaveError != null)
          Material(
            color: Colors.red[50],
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                _inlineSaveError!,
                style: TextStyle(color: Colors.red[900], fontSize: 12),
              ),
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _buildStageHeader(),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildActiveStepPanel(catalog, isEdit),
                ),
              ),
            ],
          ),
        ),
        _buildNavBar(catalog, isEdit),
      ],
    );
  }

  InputDecoration _fieldDeco(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
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
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }

  InputDecoration _compactFieldDeco(String label, {String? prefixText}) {
    return InputDecoration(
      labelText: label,
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
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    );
  }

  Widget _buildStepSupplier(List<Map<String, dynamic>> catalog, bool isEdit) {
    final draft = ref.watch(purchaseDraftProvider);
    return Column(
      key: _supplierSectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          if (isEdit && _editHumanId != null) ...[
            Text(
              'Purchase ID: $_editHumanId',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
          ] else if (!isEdit && _previewHumanId != null) ...[
            Text(
              'Purchase ID (preview): $_previewHumanId',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: HexaColors.brandPrimary,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (isEdit && _loadedDerivedStatus != null) ...[
            Text(
              'Payment: $_loadedDerivedStatus · Bal ₹${(_loadedRemaining ?? 0).toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 8),
          ],
          Text('Date *', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: draft.purchaseDate ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (date != null) {
                ref.read(purchaseDraftProvider.notifier).setPurchaseDate(date);
                _onDraftChanged();
                setState(() {});
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[50],
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today,
                      size: 18, color: HexaColors.brandPrimary),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('dd MMM yyyy')
                        .format(draft.purchaseDate ?? DateTime.now()),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Supplier *', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _buildSupplierSearch(catalog),
          if (_supplierFieldError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _supplierFieldError!,
                style: TextStyle(color: Colors.red[800], fontSize: 12),
              ),
            ),
          if (draft.supplierId != null && draft.supplierId!.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  ref.read(purchaseDraftProvider.notifier).clearSupplier();
                  _supplierCtrl.clear();
                  _syncControllersFromDraft();
                  setState(() {});
                  _onDraftChanged();
                },
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Change supplier'),
              ),
            ),
          const SizedBox(height: 12),
          const Text('Invoice (optional)'),
          TextField(
            controller: _invoiceCtrl,
            decoration: _fieldDeco('Invoice #'),
            onChanged: (s) {
              ref.read(purchaseDraftProvider.notifier).setInvoiceText(s);
              _onDraftChanged();
            },
          ),
          const SizedBox(height: 12),
          _buildBrokerBlock(),
      ],
    );
  }

  Widget _buildSupplierSearch(List<Map<String, dynamic>> catalog) {
    final av = ref.watch(suppliersListProvider);
    return av.when(
      data: (list) => _supplierColumn(list),
      error: (_, __) {
        if (_lastGoodSuppliers != null) return _supplierColumn(_lastGoodSuppliers!);
        return const Text('Could not load suppliers');
      },
      loading: () {
        if (_lastGoodSuppliers != null) {
          return _supplierColumn(_lastGoodSuppliers!);
        }
        return const LinearProgressIndicator();
      },
    );
  }

  Widget _supplierColumn(List<Map<String, dynamic>> list) {
    if (list.isEmpty) {
      return const Text(
        'No suppliers in this workspace yet — add one under Suppliers or run bootstrap.',
        style: TextStyle(fontSize: 12),
      );
    }
    final items = <InlineSearchItem>[
      for (final m in list)
        if (_supplierRowId(m).isNotEmpty)
          InlineSearchItem(
            id: _supplierRowId(m),
            label: _supplierMapLabel(m),
            subtitle: m['gst_number']?.toString(),
          ),
    ];
    return InlineSearchField(
      key: const ValueKey('purchase_supplier_search'),
      controller: _supplierCtrl,
      placeholder: 'Type at least 1 letter, then pick from the list…',
      prefixIcon: const Icon(Icons.business),
      items: items,
      onSelected: (it) {
        if (it.id.isEmpty) return;
        _applySupplierSelection(list, it);
      },
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
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton.icon(
              onPressed: _applyBrokerFromSupplierRow,
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Use supplier’s default broker'),
            ),
          ),
        if (draft.brokerId != null && draft.brokerId!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    draft.brokerIdFromSupplier != null &&
                            draft.brokerIdFromSupplier == draft.brokerId
                        ? 'From supplier: ${draft.brokerName ?? "Broker"}'
                        : 'Manual: ${draft.brokerName ?? "Broker"}',
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
    return InlineSearchField(
      key: const ValueKey('purchase_broker_search'),
      controller: _brokerCtrl,
      placeholder: 'Search broker (optional)…',
      prefixIcon: const Icon(Icons.person_search_outlined),
      items: items,
      onSelected: (it) {
        if (it.id.isEmpty) return;
        _applyBrokerSelection(list, it);
      },
    );
  }

  Widget _buildStepTerms(
    List<Map<String, dynamic>> catalog,
    bool isEdit,
  ) {
    final draft = ref.watch(purchaseDraftProvider);
    if (draft.supplierId == null) {
      return const Text('Select a supplier on step 1 first.');
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (draft.supplierName != null && draft.supplierName!.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_fix_high, size: 16, color: Color(0xFF0D9488)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Auto-filled from ${draft.supplierName}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF0D9488),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          TextField(
            controller: _paymentDaysCtrl,
            keyboardType: TextInputType.number,
            decoration: _fieldDeco('Payment days'),
            onChanged: (s) {
              ref.read(purchaseDraftProvider.notifier).setPaymentDaysText(s);
              setState(() {});
              _onDraftChanged();
            },
          ),
          if (_paymentDaysCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _duePreviewText(),
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF0D9488),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _deliveredRateCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _compactFieldDeco('Delivered rate'),
                  onChanged: (s) {
                    ref.read(purchaseDraftProvider.notifier).setDeliveredText(s);
                    _onDraftChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _billtyRateCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _compactFieldDeco('Billty rate'),
                  onChanged: (s) {
                    ref.read(purchaseDraftProvider.notifier).setBilltyText(s);
                    _onDraftChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _freightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _compactFieldDeco('Freight', prefixText: '₹ '),
                  onChanged: (s) {
                    ref.read(purchaseDraftProvider.notifier).setFreightText(s);
                    _onDraftChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InputDecorator(
                  decoration: _compactFieldDeco('Freight type'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _freightType,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(
                            value: 'separate', child: Text('Separate')),
                        DropdownMenuItem(
                            value: 'included', child: Text('Included')),
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
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commissionCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _compactFieldDeco('Broker commission %'),
            onChanged: (s) {
              ref.read(purchaseDraftProvider.notifier).setCommissionText(s);
              _onDraftChanged();
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _headerDiscCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _compactFieldDeco('Header discount % (optional)'),
            onChanged: (s) {
              ref.read(purchaseDraftProvider.notifier).setHeaderDiscountFromText(s);
              setState(() {});
              _onDraftChanged();
            },
          ),
        ],
    );
  }

  Widget _buildStepItems(
    List<Map<String, dynamic>> catalog,
    bool isEdit,
  ) {
    final draft = ref.watch(purchaseDraftProvider);
    final lines = draft.lines;
    return Column(
      key: _itemsSectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: draft.supplierId == null
              ? null
              : () => _openItemSheet(catalog),
          icon: const Icon(Icons.add, size: 20),
          label: const Text('Add item'),
        ),
        const SizedBox(height: 8),
        if (lines.isEmpty)
          const Text(
            'No items yet. Tap Add item.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
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
            final sc = it.sellingPrice;
            var profit = 0.0;
            if (sc != null) {
              profit = (sc - it.landingCost) * it.qty;
            }
            final kpu = it.kgPerUnit;
            final lck = it.landingCostPerKg;
            final sub = (kpu != null &&
                    lck != null &&
                    kpu > 0)
                ? '${it.qty} ${it.unit} · ₹${lck.toStringAsFixed(0)}/kg → line ₹${total.toStringAsFixed(0)}'
                : '${it.qty} ${it.unit} · landing ₹${it.landingCost.toStringAsFixed(0)} → line ₹${total.toStringAsFixed(0)}';
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                title: Text(it.itemName, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '$sub${profit != 0 ? ' · Profit ₹${profit.toStringAsFixed(0)}' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => _openItemSheet(catalog, editIndex: i),
                      child: const Text('Edit'),
                    ),
                    TextButton(
                      onPressed: () => _removeLineAt(i),
                      child: Text('Delete', style: TextStyle(color: Colors.red[800])),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildStepSummary(
    List<Map<String, dynamic>> catalog,
    bool isEdit,
  ) {
    final draft = ref.watch(purchaseDraftProvider);
    final b = ref.watch(purchaseStrictBreakdownProvider);
    final qtot = ref.watch(purchaseQuantityTotalsProvider);
    final saveVal = ref.watch(purchaseSaveValidationProvider);
    final canSave = saveVal.isOk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isEditMode() && _loadedDerivedStatus != null) ...[
          Text(
            'Payment: $_loadedDerivedStatus',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
        ],

        // ── ITEMS ─────────────────────────────────────────────────────────
        const Text('Items',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (draft.lines.isEmpty)
          const Text('No items added.',
              style: TextStyle(fontSize: 12, color: Colors.black54))
        else
          ...draft.lines.asMap().entries.map((entry) {
            final it = entry.value;
            final calc = TradeCalcLine(
              qty: it.qty,
              landingCost: it.landingCost,
              kgPerUnit: it.kgPerUnit,
              landingCostPerKg: it.landingCostPerKg,
              taxPercent: it.taxPercent,
              discountPercent: it.lineDiscountPercent,
            );
            final lineTotal = lineMoney(calc);
            final kpu = it.kgPerUnit;
            final lck = it.landingCostPerKg;
            final rateStr = (kpu != null && lck != null && kpu > 0 && lck > 0)
                ? '${_fmtN(it.qty)} ${it.unit} × ₹${_fmtN(lck)}/kg'
                : '${_fmtN(it.qty)} ${it.unit} × ₹${_fmtN(it.landingCost)}/${it.unit}';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: HexaColors.brandBorder),
                  borderRadius: BorderRadius.circular(10),
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
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            rateStr,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₹${lineTotal.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ],
                ),
              ),
            );
          }),

        const SizedBox(height: 14),

        // ── TOTALS ────────────────────────────────────────────────────────
        const Text('Totals',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (qtot.totalKg > 0)
          _summaryRow(
              'Total mass', '${qtot.totalKg.toStringAsFixed(0)} kg'),
        _summaryRow('Subtotal', '₹${b.subtotalGross.toStringAsFixed(0)}'),
        if (b.taxTotal > 0)
          _summaryRow('Tax', '₹${b.taxTotal.toStringAsFixed(0)}'),
        if (b.discountTotal > 0)
          _summaryRow('Discount', '- ₹${b.discountTotal.toStringAsFixed(0)}',
              valueColor: Colors.red[700]),
        if (b.freight > 0)
          _summaryRow('Freight', '₹${b.freight.toStringAsFixed(0)}'),
        if (b.commission > 0)
          _summaryRow('Broker', '₹${b.commission.toStringAsFixed(0)}'),
        const Divider(height: 16),
        _summaryRow('Final', '₹${b.grand.toStringAsFixed(0)}',
            emphasize: true),
        const SizedBox(height: 16),

        // ── NAV CHIPS ─────────────────────────────────────────────────────
        Wrap(
          spacing: 6,
          children: [
            ActionChip(
              label: const Text('Edit supplier'),
              onPressed: () => setState(() => _currentStep = 0),
            ),
            ActionChip(
              label: const Text('Edit terms'),
              onPressed: () => setState(() => _currentStep = 1),
            ),
            ActionChip(
              label: const Text('Edit items'),
              onPressed: () => setState(() => _currentStep = 2),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: (_isSaving || !canSave) ? null : _validateAndSave,
          child: _isSaving
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(isEdit ? 'Save changes' : 'Save purchase'),
        ),
        if (!canSave)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              saveVal.errorMessage ??
                  'Complete supplier and at least one valid line to save.',
              style: TextStyle(color: Colors.red[800], fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// Compact number: no trailing `.0` for integers.
  String _fmtN(double n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);

  Widget _summaryRow(String label, String value,
      {bool emphasize = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: emphasize ? 14 : 13,
              fontWeight:
                  emphasize ? FontWeight.w700 : FontWeight.w500,
              color: emphasize
                  ? const Color(0xFF0F172A)
                  : const Color(0xFF64748B),
            ),
          ),
          Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight:
                  emphasize ? FontWeight.w900 : FontWeight.w700,
              fontSize: emphasize ? 17 : 13,
              color: emphasize
                  ? const Color(0xFF15803D)
                  : valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavBar(List<Map<String, dynamic>> catalog, bool isEdit) {
    final g = ref.watch(purchaseStepGatesProvider);
    final showNext = _currentStep < 3;
    return SafeArea(
      child: Material(
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              if (_currentStep > 0)
                TextButton(
                  onPressed: _onBack,
                  child: const Text('Back'),
                ),
              const Spacer(),
              if (showNext)
                FilledButton(
                  onPressed: _canContinueForStep(g) ? _onContinue : null,
                  child: const Text('Next'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool _canContinueForStep(
      ({bool from0, bool from1, bool from2, bool from3}) g) {
    switch (_currentStep) {
      case 0:
        return g.from0;
      case 1:
        return g.from1;
      case 2:
        return g.from2;
      default:
        return false;
    }
  }
}
