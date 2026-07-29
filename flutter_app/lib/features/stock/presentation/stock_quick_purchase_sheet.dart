import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/staff_home_providers.dart';
import '../../../core/providers/stock_providers.dart'
    show
        applyStockItemDetailPatch,
        applyStockListRowPatch,
        stockChangesFeedProvider,
        stockItemActivityProvider;
import '../../stock/stock_list_row_patch.dart' show stockStatusForPatchRow;
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../shared/widgets/inline_search_field.dart';
import '../../purchase/presentation/widgets/party_inline_suggest_field.dart';

/// Add purchase quantity for a stock row (quick purchase → system ledger +).
Future<bool> showStockQuickPurchaseSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> item,
}) async {
  final id = item['id']?.toString().trim() ?? '';
  if (id.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item not found — cannot add purchase quantity'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return false;
  }
  final safeItem = normalizeStockDetailMap(Map<String, dynamic>.from(item));
  if ((safeItem['id']?.toString() ?? '').isEmpty) {
    safeItem['id'] = id;
  }
  final result = await showHexaBottomSheet<bool>(
    context: context,
    compact: true,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: _StockQuickPurchaseBody(item: safeItem),
  );
  return result == true;
}

class _StockQuickPurchaseBody extends ConsumerStatefulWidget {
  const _StockQuickPurchaseBody({required this.item});

  final Map<String, dynamic> item;

  @override
  ConsumerState<_StockQuickPurchaseBody> createState() =>
      _StockQuickPurchaseBodyState();
}

class _StockQuickPurchaseBodyState
    extends ConsumerState<_StockQuickPurchaseBody> {
  final _qtyCtrl = TextEditingController();
  final _supplierCtrl = TextEditingController();
  final _brokerCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _qtyFocus = FocusNode();
  final _supplierFocus = FocusNode();
  final _brokerFocus = FocusNode();
  final _notesFocus = FocusNode();
  bool _saving = false;
  bool _intelLoaded = false;
  String? _qtyError;
  String? _supplierError;
  String? _brokerError;
  InlineSearchItem? _supplier;
  InlineSearchItem? _broker;
  late Map<String, dynamic> _item;
  late final String _idempotencyKey;

  String get _itemId => _item['id']?.toString().trim() ?? '';

  String get _name {
    final n = _item['name']?.toString().trim() ?? '';
    if (n.isNotEmpty) return n;
    final code = _itemCode;
    return code.isNotEmpty ? code : 'Item';
  }

  String get _itemCode =>
      (_item['item_code'] ?? _item['sku'] ?? _item['barcode'])
          ?.toString()
          .trim() ??
      '';

  String get _unit {
    final u = (_item['stock_unit'] ?? _item['unit'])?.toString().trim() ?? '';
    return u.isNotEmpty ? u : 'piece';
  }

  String get _unitLabel => _unit.toUpperCase();

  String get _warehouseLabel {
    final session = ref.read(sessionProvider);
    final title = session?.primaryBusiness.effectiveDisplayTitle.trim() ?? '';
    return title.isNotEmpty ? title : 'Warehouse';
  }

  double get _currentStock {
    final v = coerceToDouble(_item['current_stock']);
    return v.isFinite ? v : 0;
  }

  double? get _enteredQty {
    final t = _qtyCtrl.text.trim().replaceAll(',', '');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null || !v.isFinite || v <= 0) return null;
    return v;
  }

  double? get _updatedStock {
    final q = _enteredQty;
    if (q == null) return null;
    return _currentStock + q;
  }

  String? get _historyLabel {
    final by = _item['last_stock_updated_by']?.toString().trim();
    final atRaw = _item['last_stock_updated_at']?.toString().trim();
    final lastQty = coerceToDoubleNullable(_item['last_line_qty']);
    if ((by == null || by.isEmpty) &&
        (atRaw == null || atRaw.isEmpty) &&
        lastQty == null) {
      return null;
    }
    String? when;
    if (atRaw != null && atRaw.isNotEmpty) {
      final dt = DateTime.tryParse(atRaw);
      if (dt != null) {
        when = DateFormat('d MMM · HH:mm').format(dt.toLocal());
      }
    }
    final parts = <String>[];
    if (lastQty != null && lastQty.isFinite && lastQty > 0) {
      parts.add(
        'last line ${formatStockQtyForUnit(_unit, lastQty)} $_unitLabel',
      );
    }
    if (by != null && by.isNotEmpty) parts.add(by);
    if (when != null) parts.add(when);
    if (parts.isEmpty) return null;
    return 'History: ${parts.join(' · ')}';
  }

  @override
  void initState() {
    super.initState();
    _item = normalizeStockDetailMap(Map<String, dynamic>.from(widget.item));
    if ((_item['id']?.toString() ?? '').isEmpty &&
        (widget.item['id']?.toString() ?? '').isNotEmpty) {
      _item['id'] = widget.item['id'];
    }
    _idempotencyKey =
        'quick-purchase:$_itemId:${DateTime.now().microsecondsSinceEpoch}';
    _qtyCtrl.addListener(_onQtyChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadSmartDefaults());
    });
  }

  void _onQtyChanged() {
    if (!mounted) return;
    setState(() {
      _qtyError = _qtyErrorText();
    });
  }

  String? _qtyErrorText() {
    final t = _qtyCtrl.text.trim();
    if (t.isEmpty) return null; // don't yell until save / typing invalid
    final v = double.tryParse(t.replaceAll(',', ''));
    if (v == null || !v.isFinite || v <= 0) {
      return 'Enter a valid purchase quantity';
    }
    return null;
  }

  @override
  void dispose() {
    _qtyCtrl.removeListener(_onQtyChanged);
    _qtyCtrl.dispose();
    _supplierCtrl.dispose();
    _brokerCtrl.dispose();
    _notesCtrl.dispose();
    _qtyFocus.dispose();
    _supplierFocus.dispose();
    _brokerFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  InlineSearchItem _partyItem(Map<String, dynamic> row) {
    final id = row['id']?.toString().trim() ?? '';
    final name = row['name']?.toString().trim() ?? '';
    final phone = row['phone']?.toString();
    final location = row['location']?.toString() ?? row['address']?.toString();
    return InlineSearchItem(
      id: id,
      label: name.isNotEmpty ? name : (id.isNotEmpty ? id : 'Unknown'),
      subtitle: [
        if (phone != null && phone.trim().isNotEmpty) phone.trim(),
        if (location != null && location.trim().isNotEmpty) location.trim(),
      ].join(' • '),
      searchText: '$name ${phone ?? ''} ${location ?? ''}',
    );
  }

  bool _selectionMatches(
    InlineSearchItem? selected,
    TextEditingController ctrl,
  ) {
    if (selected == null || selected.id.isEmpty) return false;
    return ctrl.text.trim().toLowerCase() ==
        selected.label.trim().toLowerCase();
  }

  Future<void> _loadSmartDefaults() async {
    final session = ref.read(sessionProvider);
    if (session == null || _itemId.isEmpty) {
      if (mounted) setState(() => _intelLoaded = true);
      return;
    }
    try {
      final intel = await ref.read(hexaApiProvider).getItemPurchaseIntelligence(
            businessId: session.primaryBusiness.id,
            itemId: _itemId,
          );
      if (!mounted) return;
      final suggested = coerceToDoubleNullable(intel['suggested_qty']);
      if (_qtyCtrl.text.trim().isEmpty &&
          suggested != null &&
          suggested.isFinite &&
          suggested > 0) {
        _qtyCtrl.text = suggested == suggested.roundToDouble()
            ? suggested.toStringAsFixed(0)
            : formatStockQtyForUnit(_unit, suggested);
      }
      setState(() => _intelLoaded = true);
    } catch (_) {
      if (mounted) setState(() => _intelLoaded = true);
    }
  }

  void _rollbackOptimistic(double previousStock) {
    if (_itemId.isEmpty) return;
    final patch = <String, dynamic>{
      'current_stock': previousStock,
      'stock_status': stockStatusForPatchRow({
        'current_stock': previousStock,
        'reorder_level': _item['reorder_level'],
      }),
    };
    applyStockListRowPatch(ref, itemId: _itemId, patch: patch);
    applyStockItemDetailPatch(ref, itemId: _itemId, patch: patch);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!mounted || _saving) return;

    final session = ref.read(sessionProvider);
    if (session == null) {
      setState(() => _qtyError = 'Sign in again to save');
      return;
    }
    if (_itemId.isEmpty) {
      setState(() => _qtyError = 'Item missing — close and try again');
      return;
    }

    final parsed = _enteredQty;
    var ok = true;
    setState(() {
      if (parsed == null) {
        _qtyError = _qtyCtrl.text.trim().isEmpty
            ? 'Enter a quantity'
            : 'Enter a valid purchase quantity';
        ok = false;
      } else {
        _qtyError = null;
      }
      if (!_selectionMatches(_supplier, _supplierCtrl)) {
        _supplierError = 'Select a supplier from suggestions';
        ok = false;
      } else {
        _supplierError = null;
      }
      if (_brokerCtrl.text.trim().isNotEmpty &&
          !_selectionMatches(_broker, _brokerCtrl)) {
        _brokerError = 'Select broker from suggestions or clear it';
        ok = false;
      } else {
        _brokerError = null;
      }
    });
    if (!ok || parsed == null) return;

    final supplierId = _supplier!.id.trim();
    if (supplierId.isEmpty) {
      setState(() => _supplierError = 'Select a supplier from suggestions');
      return;
    }

    final previousStock = _currentStock;
    final optimisticStock = previousStock + parsed;
    setState(() => _saving = true);

    final optimisticPatch = <String, dynamic>{
      'current_stock': optimisticStock,
      'stock_status': stockStatusForPatchRow({
        'current_stock': optimisticStock,
        'reorder_level': _item['reorder_level'],
      }),
    };
    try {
      applyStockListRowPatch(ref, itemId: _itemId, patch: optimisticPatch);
      applyStockItemDetailPatch(ref, itemId: _itemId, patch: optimisticPatch);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[QUICK_PURCHASE] optimistic patch failed: $e\n$st');
      }
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final saved = await ref.read(hexaApiProvider).createStockQuickPurchase(
            businessId: session.primaryBusiness.id,
            itemId: _itemId,
            qty: parsed,
            supplierId: supplierId,
            brokerId: _brokerCtrl.text.trim().isEmpty ? null : _broker?.id,
            notes: _notesCtrl.text,
            idempotencyKey: _idempotencyKey,
          );

      final itemOut = saved['item'];
      final authoritative = itemOut is Map
          ? coerceToDoubleNullable(
              Map<String, dynamic>.from(itemOut)['current_stock'],
            )
          : coerceToDoubleNullable(saved['current_stock']);
      final finalQty =
          (authoritative != null && authoritative.isFinite)
              ? authoritative
              : optimisticStock;
      final confirmPatch = <String, dynamic>{
        'current_stock': finalQty,
        'stock_status': stockStatusForPatchRow({
          'current_stock': finalQty,
          'reorder_level': _item['reorder_level'],
        }),
        'last_line_qty': parsed,
        'last_stock_updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      applyStockListRowPatch(ref, itemId: _itemId, patch: confirmPatch);
      applyStockItemDetailPatch(ref, itemId: _itemId, patch: confirmPatch);

      invalidateStockRowSaveSurfaces(
        ref,
        itemId: _itemId,
        refreshItemDetail: true,
      );
      invalidatePurchaseListSurfacesLight(ref);
      ref.invalidate(stockChangesFeedProvider);
      ref.invalidate(stockItemActivityProvider(_itemId));
      ref.invalidate(staffTodayActivityProvider);
      ref.invalidate(staffTodayStockWorkProvider);
      ref.invalidate(staffTodaySummaryProvider);

      unawaited(HapticFeedback.mediumImpact());
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Purchase added — stock now ${formatStockQtyForUnit(_unit, finalQty)} $_unitLabel',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      _rollbackOptimistic(previousStock);
      if (!mounted) return;
      final msg = e is DioException
          ? friendlyApiError(e)
          : userFacingError(e);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
      setState(() => _saving = false);
    }
  }

  InputDecoration _fieldDecoration({
    required String hint,
    Widget? prefixIcon,
    String? suffixText,
    String? errorText,
  }) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: HexaColors.brandBackground,
      prefixIcon: prefixIcon,
      suffixText: suffixText,
      errorText: errorText,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: HexaColors.brandBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: HexaColors.brandBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: HexaColors.brandAccent, width: 1.5),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: HexaDsType.label(12).copyWith(
          fontWeight: FontWeight.w700,
          color: HexaColors.textBody,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildForm(context);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[QUICK_PURCHASE] build failed: $e\n$st');
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Could not open add purchase quantity',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 8),
            const Text(
              'Close and try again from the stock list.',
              style: TextStyle(fontSize: 13, color: HexaColors.neutral),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildForm(BuildContext context) {
    final suppliers = ref.watch(suppliersListProvider);
    final brokers = ref.watch(brokersListProvider);
    final supplierItems = (suppliers.valueOrNull ?? const [])
        .map((e) => _partyItem(Map<String, dynamic>.from(e as Map)))
        .where((it) => it.id.isNotEmpty)
        .toList();
    final brokerItems = (brokers.valueOrNull ?? const [])
        .map((e) => _partyItem(Map<String, dynamic>.from(e as Map)))
        .where((it) => it.id.isNotEmpty)
        .toList();
    final stockLabel = stockDisplayPrimary(_currentStock, _unit);
    final updated = _updatedStock;
    final history = _historyLabel;
    final desktop = HexaBreakpoints.isDesktop(context);
    final suppliersFailed = suppliers.hasError && suppliers.valueOrNull == null;
    final brokersFailed = brokers.hasError && brokers.valueOrNull == null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add purchase quantity',
                    style: HexaDsType.label(11).copyWith(
                      fontWeight: FontWeight.w800,
                      color: HexaColors.brandAccent,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: HexaDsType.h3(context).copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Cancel',
              icon: const Icon(Icons.close_rounded, size: 22),
              onPressed:
                  _saving ? null : () => Navigator.of(context).pop(false),
            ),
          ],
        ),
        if (_itemCode.isNotEmpty)
          Text(
            'Product: $_itemCode',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: HexaColors.neutral,
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'Warehouse: $_warehouseLabel',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: HexaColors.neutral,
          ),
        ),
        if (history != null) ...[
          const SizedBox(height: 4),
          Text(
            history,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: HexaColors.neutral,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: HexaColors.brandPrimary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: HexaColors.brandPrimary.withValues(alpha: 0.12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 18,
                    color: HexaColors.brandPrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Existing stock · $stockLabel',
                      style: HexaDsType.bodySm(context).copyWith(
                        fontWeight: FontWeight.w700,
                        color: HexaColors.brandPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              if (updated != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Updated stock · ${stockDisplayPrimary(updated, _unit)}'
                  '  (+${formatStockQtyForUnit(_unit, _enteredQty!)} $_unitLabel)',
                  style: HexaDsType.bodySm(context).copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF15803D),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 4),
                Text(
                  'Updated stock · enter quantity to preview',
                  style: HexaDsType.label(11).copyWith(
                    fontWeight: FontWeight.w600,
                    color: HexaColors.neutral,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!_intelLoaded) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
        const SizedBox(height: 12),
        _fieldLabel('Purchase quantity'),
        TextField(
          controller: _qtyCtrl,
          focusNode: _qtyFocus,
          autofocus: true,
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
          ],
          onSubmitted: (_) => _supplierFocus.requestFocus(),
          decoration: _fieldDecoration(
            hint: 'e.g. 100',
            suffixText: _unitLabel,
            errorText: _qtyError,
          ),
        ),
        const SizedBox(height: 10),
        _fieldLabel('Supplier'),
        if (suppliersFailed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Could not load suppliers',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: HexaDsColors.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(suppliersListProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        PartyInlineSuggestField(
          controller: _supplierCtrl,
          focusNode: _supplierFocus,
          hintText:
              suppliers.isLoading ? 'Loading suppliers…' : 'Search supplier…',
          prefixIcon: const Icon(Icons.store_outlined, size: 18),
          minQueryLength: 0,
          maxMatches: 8,
          dense: true,
          suggestionsAsOverlay: true,
          textInputAction: TextInputAction.next,
          focusAfterSelection: _brokerFocus,
          items: supplierItems,
          onSelected: _saving
              ? (_) {}
              : (it) {
                  setState(() {
                    _supplier = it;
                    _supplierError = null;
                  });
                },
        ),
        if (_supplierError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _supplierError!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: HexaDsColors.error,
              ),
            ),
          ),
        const SizedBox(height: 10),
        _fieldLabel('Broker (optional)'),
        if (brokersFailed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Could not load brokers',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: HexaDsColors.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(brokersListProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        PartyInlineSuggestField(
          controller: _brokerCtrl,
          focusNode: _brokerFocus,
          hintText: brokers.isLoading ? 'Loading brokers…' : 'Search broker…',
          prefixIcon: const Icon(Icons.person_search_outlined, size: 18),
          minQueryLength: 0,
          maxMatches: 8,
          dense: true,
          suggestionsAsOverlay: true,
          textInputAction: TextInputAction.next,
          focusAfterSelection: _notesFocus,
          items: brokerItems,
          onSelected: _saving
              ? (_) {}
              : (it) {
                  setState(() {
                    _broker = it;
                    _brokerError = null;
                  });
                },
        ),
        if (_brokerError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _brokerError!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: HexaDsColors.error,
              ),
            ),
          ),
        const SizedBox(height: 10),
        _fieldLabel('Notes (optional)'),
        TextField(
          controller: _notesCtrl,
          focusNode: _notesFocus,
          enabled: !_saving,
          minLines: 2,
          maxLines: 3,
          textInputAction: TextInputAction.done,
          decoration: _fieldDecoration(hint: 'Optional notes…'),
        ),
        const SizedBox(height: 14),
        if (desktop)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: HexaColors.brandPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Add purchase',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ],
          )
        else
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: HexaColors.brandPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Add purchase',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
          ),
      ],
    );
  }
}
