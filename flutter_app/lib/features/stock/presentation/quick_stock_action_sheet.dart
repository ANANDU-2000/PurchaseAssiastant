import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/auth/session_permissions.dart';
import '../../../core/debug/stock_api_storm_monitor.dart';
import '../../../core/stock/stock_version_retry.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/json_coerce.dart';
import '../../../core/providers/business_aggregates_invalidation.dart'
    show invalidateStockRowSaveSurfaces;
import '../../../core/providers/business_write_event.dart'
    show emitBusinessWriteEvent;
import '../../../core/notifications/local_notifications_service.dart';
import '../../../core/providers/stock_providers.dart'
    show
        applyStockItemDetailPatch,
        applyStockListRowPatch,
        clearStockItemDetailPatch,
        clearStockListRowPatchesForIds,
        stockChangesFeedProvider,
        stockItemActivityProvider,
        stockStatusCountsProvider;
import '../stock_list_row_patch.dart'
    show
        stockListPatchFromPhysicalCount,
        stockListPatchFromPreSaveRow,
        stockListPatchFromStockDetail,
        stockStatusForPatchRow;
import '../../../core/providers/notification_center_provider.dart';
import '../../../core/providers/server_notifications_provider.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/design_system/widgets/app_form_layout.dart';
import 'widgets/stock_update_mode_toggle.dart';
import 'stock_undo_snackbar.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
const _kReasonChips = <(String label, String type)>[
  ('Physical count', 'verification'),
  ('Sale', 'sale'),
  ('Damage', 'damaged'),
  ('Correction', 'correction'),
  ('Wastage', 'damaged'),
];

/// Quick physical / system stock update (patch / compact update).
Future<bool> showQuickStockActionSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> item,
  StockUpdateMode initialMode = StockUpdateMode.physical,
  bool skipInitialRefresh = false,
  bool refreshItemDetail = false,
  /// When false, staff can only edit floor remaining (Physical).
  bool allowSystem = true,
}) async {
  final id = item['id']?.toString().trim() ?? '';
  if (id.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item not found — cannot update stock'),
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
  final mode = allowSystem ? initialMode : StockUpdateMode.physical;
  final result = await showHexaBottomSheet<bool>(
    context: context,
    compact: true,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: _QuickStockActionBody(
      item: safeItem,
      parentRef: ref,
      initialMode: mode,
      skipInitialRefresh: skipInitialRefresh,
      refreshItemDetail: refreshItemDetail,
      allowSystem: allowSystem,
    ),
  );
  return result == true;
}

class _QuickStockActionBody extends ConsumerStatefulWidget {
  const _QuickStockActionBody({
    required this.item,
    required this.parentRef,
    this.initialMode = StockUpdateMode.physical,
    this.skipInitialRefresh = false,
    this.refreshItemDetail = false,
    this.allowSystem = true,
  });

  final Map<String, dynamic> item;
  final WidgetRef parentRef;
  final StockUpdateMode initialMode;
  final bool skipInitialRefresh;
  final bool refreshItemDetail;
  final bool allowSystem;

  @override
  ConsumerState<_QuickStockActionBody> createState() =>
      _QuickStockActionBodyState();
}

class _QuickStockActionBodyState extends ConsumerState<_QuickStockActionBody> {
  bool _saving = false;
  bool _refreshing = false;
  String? _refreshError;
  Map<String, dynamic>? _preSaveItemSnapshot;
  late Map<String, dynamic> _item;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _notesCtrl;
  late double _current;
  String? _reasonType = 'verification';
  String _reasonLabel = 'Physical count';
  late StockUpdateMode _mode;
  String? _qtyError;
  String? _reasonError;

  @override
  void initState() {
    super.initState();
    _item = normalizeStockDetailMap(Map<String, dynamic>.from(widget.item));
    if ((_item['id']?.toString() ?? '').isEmpty &&
        (widget.item['id']?.toString() ?? '').isNotEmpty) {
      _item['id'] = widget.item['id'];
    }
    _mode = widget.initialMode;
    _current = _seedQtyForMode(_mode);
    _qtyCtrl = TextEditingController(
      text: formatStockQtyForUnit(_unit, _current),
    );
    _notesCtrl = TextEditingController();
    _qtyCtrl.addListener(_revalidateQty);
    if (!widget.skipInitialRefresh && !_itemIsFresh(_item)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refreshItemFromServer());
      });
    }
  }

  double _seedQtyForMode(StockUpdateMode mode) {
    if (mode == StockUpdateMode.physical) {
      final phys = coerceToDoubleNullable(_item['physical_stock_qty']);
      if (phys != null && phys.isFinite && phys >= 0) return phys;
    }
    final sys = coerceToDouble(_item['current_stock']);
    return sys.isFinite ? sys : 0;
  }

  /// Returns true when the passed item has enough data to skip a fresh API fetch.
  static bool _itemIsFresh(Map<String, dynamic> item) {
    if (item['current_stock'] == null) return false;
    final updatedAt = item['last_stock_updated_at']?.toString();
    if (updatedAt == null || updatedAt.isEmpty) return false;
    final dt = DateTime.tryParse(updatedAt);
    if (dt == null) return false;
    return DateTime.now().difference(dt).inMinutes < 5;
  }

  int? _stockVersion() => stockVersionFromItem(_item);

  Future<void> _applyFreshItem(Map<String, dynamic> fresh) async {
    if (!mounted) return;
    setState(() {
      _item = Map<String, dynamic>.from(fresh);
      _current = _seedQtyForMode(_mode);
      _qtyCtrl.text = formatStockQtyForUnit(_unit, _current);
    });
  }

  Future<bool> _refreshItemFromServer() async {
    final session = ref.read(sessionProvider);
    if (session == null || _itemId.isEmpty) return false;
    if (mounted) {
      setState(() {
        _refreshing = true;
        _refreshError = null;
      });
    }
    try {
      final fresh = await ref.read(hexaApiProvider).getStockItem(
            businessId: session.primaryBusiness.id,
            itemId: _itemId,
          );
      if (!mounted) return false;
      if (fresh.isEmpty) {
        setState(() {
          _refreshing = false;
          _refreshError = 'Could not refresh stock — using last known values';
        });
        return false;
      }
      await _applyFreshItem(normalizeStockDetailMap(fresh));
      if (mounted) setState(() => _refreshing = false);
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _refreshError = 'Could not refresh stock — using last known values';
        });
      }
      return false;
    }
  }

  void _onModeChanged(StockUpdateMode mode) {
    setState(() {
      _mode = mode;
      _current = _seedQtyForMode(mode);
      _qtyCtrl.text = formatStockQtyForUnit(_unit, _current);
      _reasonError = null;
      if (mode == StockUpdateMode.physical) {
        _reasonType = 'verification';
        _reasonLabel = 'Physical count';
      } else {
        _reasonType = 'correction';
        _reasonLabel = 'Correction';
      }
      _qtyError = _qtyErrorText();
    });
  }

  double? _parseEnteredQty() {
    final t = _qtyCtrl.text.trim().replaceAll(',', '');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null || !v.isFinite || v < 0) return null;
    return v;
  }

  String? _qtyErrorText() {
    if (_parseEnteredQty() != null) return null;
    final t = _qtyCtrl.text.trim();
    if (t.isEmpty) return 'Enter a quantity';
    return 'Enter a valid quantity';
  }

  void _revalidateQty() {
    if (!mounted) return;
    final next = _qtyErrorText();
    setState(() => _qtyError = next);
  }

  bool get _canSave {
    final parsedQty = _parseEnteredQty();
    return !_saving &&
        _itemId.isNotEmpty &&
        parsedQty != null &&
        (_mode == StockUpdateMode.physical ||
            (_reasonType != null && _reasonType!.isNotEmpty));
  }

  void _onSavePressed() {
    unawaited(_save());
  }

  @override
  void dispose() {
    _qtyCtrl.removeListener(_revalidateQty);
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

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

  String get _unitLabel => _unit.isNotEmpty ? _unit.toUpperCase() : '';

  String get _warehouseLabel {
    final session = ref.read(sessionProvider);
    final title = session?.primaryBusiness.effectiveDisplayTitle.trim() ?? '';
    return title.isNotEmpty ? title : 'Warehouse';
  }

  /// Live difference: entered physical qty − system ledger.
  double? get _liveDiff {
    final entered = _parseEnteredQty();
    if (entered == null) return null;
    final system = coerceToDouble(_item['current_stock']);
    if (!system.isFinite) return entered;
    return entered - system;
  }

  /// System-mode adjustment: entered system qty − current system qty.
  double? get _systemAdjustmentVariance {
    if (_mode != StockUpdateMode.system) return null;
    final entered = _parseEnteredQty();
    if (entered == null) return null;
    final system = coerceToDouble(_item['current_stock']);
    if (!system.isFinite) return entered;
    return entered - system;
  }

  double? get _physicalQty {
    final phys = coerceToDoubleNullable(_item['physical_stock_qty']);
    if (phys == null || !phys.isFinite) return null;
    return phys;
  }

  /// Physical − system (ledger variance), independent of the qty field.
  double? get _physicalVsSystemVariance {
    final phys = _physicalQty;
    if (phys == null) return null;
    final system = coerceToDouble(_item['current_stock']);
    if (!system.isFinite) return phys;
    return phys - system;
  }

  String? get _historyLabel {
    final by = _item['last_stock_updated_by']?.toString().trim();
    final atRaw = _item['last_stock_updated_at']?.toString().trim();
    if ((by == null || by.isEmpty) && (atRaw == null || atRaw.isEmpty)) {
      return null;
    }
    String? when;
    if (atRaw != null && atRaw.isNotEmpty) {
      final dt = DateTime.tryParse(atRaw);
      if (dt != null) {
        when = DateFormat('d MMM · HH:mm').format(dt.toLocal());
      }
    }
    if (by != null && by.isNotEmpty && when != null) {
      return 'History: last system edit by $by · $when';
    }
    if (by != null && by.isNotEmpty) return 'History: last system edit by $by';
    if (when != null) return 'History: last system edit · $when';
    return null;
  }

  String get _approvalNote {
    final session = ref.read(sessionProvider);
    if (session == null) {
      return 'Approval: sign in again before saving system stock.';
    }
    if (sessionIsPrivilegedStockRole(session)) {
      return 'Approval: applies immediately (owner/manager). Undo available for 15 min.';
    }
    return 'Approval: owner is notified when staff updates system stock.';
  }

  String? get _lastPhysicalLabel {
    final phys = coerceToDoubleNullable(_item['physical_stock_qty']);
    if (phys == null || !phys.isFinite) return null;
    final diff = coerceToDoubleNullable(_item['physical_stock_difference_qty']);
    final sign = (diff ?? 0) >= 0 ? '+' : '';
    final diffPart = diff != null && diff.abs() > 0.001
        ? ' ($sign${formatStockQtyForUnit(_unit, diff)} diff)'
        : '';
    return 'Last physical: ${formatStockQtyForUnit(_unit, phys)} $_unitLabel$diffPart';
  }

  Map<String, dynamic> _systemOptimisticFallback({
    required num parsed,
    required Map<String, dynamic> row,
  }) {
    return _systemOptimisticFallbackStatic(
      parsed: parsed,
      row: row,
    );
  }

  static Map<String, dynamic> _systemOptimisticFallbackStatic({
    required num parsed,
    required Map<String, dynamic> row,
  }) {
    final phys = coerceToDoubleNullable(row['physical_stock_qty']);
    final status = stockStatusForPatchRow({
      ...row,
      'current_stock': parsed,
    });
    return {
      'current_stock': parsed,
      if (status != null) 'stock_status': status,
      if (phys != null && phys.isFinite)
        'physical_stock_difference_qty': phys - parsed.toDouble(),
      'last_stock_updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  static Future<Map<String, dynamic>?> _persistStockWithRef({
    required WidgetRef parentRef,
    required String itemId,
    required StockUpdateMode mode,
    required num parsed,
    required String reasonLabel,
    required String? reasonType,
    required String note,
    required int? stockVersion,
    required String idempotencyKey,
  }) async {
    final session = parentRef.read(sessionProvider);
    if (session == null) return null;
    final api = parentRef.read(hexaApiProvider);
    final bid = session.primaryBusiness.id;
    if (mode == StockUpdateMode.system) {
      final detail = await api.patchStockItemWithRetry(
        businessId: bid,
        itemId: itemId,
        newQty: parsed,
        adjustmentType: reasonType ?? 'correction',
        reason: note.isNotEmpty ? '$reasonLabel — $note' : reasonLabel,
        initialStockVersion: stockVersion,
        idempotencyKey: idempotencyKey,
      );
      parentRef.invalidate(appNotificationsListProvider);
      parentRef.invalidate(notificationCenterCoordinatorProvider);
      return detail;
    }
    return api.recordPhysicalStockCount(
      businessId: bid,
      itemId: itemId,
      countedQty: parsed,
      notes: note.isNotEmpty ? '$reasonLabel — $note' : reasonLabel,
    );
  }

  void _applyOptimisticListPatch(
    Map<String, dynamic>? saved,
    num parsed, {
    WidgetRef? parentRef,
    String? itemId,
    StockUpdateMode? mode,
    Map<String, dynamic>? itemRow,
  }) {
    final ref = parentRef ?? widget.parentRef;
    final id = itemId ?? _itemId;
    final updateMode = mode ?? _mode;
    final row = itemRow ?? _item;
    if (id.isEmpty) return;
    final system = coerceToDouble(row['current_stock']);
    final reorder = row['reorder_level'];
    var patch = updateMode == StockUpdateMode.physical
        ? stockListPatchFromPhysicalCount(
            {
              ...?saved,
              if (reorder != null) 'reorder_level': reorder,
            },
            fallbackCountedQty: parsed,
            fallbackSystemQty: system,
          )
        : stockListPatchFromStockDetail(
            {
              ...?saved,
              if (reorder != null) 'reorder_level': reorder,
            },
            fallbackQty: parsed,
          );
    if (patch.isEmpty && updateMode == StockUpdateMode.physical) {
      final now = DateTime.now().toUtc().toIso8601String();
      patch = {
        'physical_stock_qty': parsed,
        'physical_stock_difference_qty': parsed - system,
        'physical_stock_counted_at': now,
      };
    }
    if (patch.isEmpty && updateMode == StockUpdateMode.system) {
      patch = _systemOptimisticFallback(
        parsed: parsed,
        row: row,
      );
    }
    if (patch.isEmpty) return;
    if (kDebugMode) {
      debugPrint('[STOCK_CACHE_REFRESH] patchKeys=${patch.keys.toList()}');
    }
    applyStockListRowPatch(ref, itemId: id, patch: patch);
    applyStockItemDetailPatch(ref, itemId: id, patch: patch);
  }

  static void _rollbackOptimisticPatchWithRef({
    required WidgetRef parentRef,
    required String itemId,
    required Map<String, dynamic> preSaveSnapshot,
  }) {
    if (itemId.isEmpty) return;
    final patch = stockListPatchFromPreSaveRow(preSaveSnapshot);
    if (patch.isEmpty) {
      // No pre-save row values to restore — drop the optimistic overlay entirely.
      clearStockListRowPatchesForIds(parentRef, [itemId]);
    } else {
      // Restore qty + stock_version/status stamps so a stale optimistic version
      // never outlives a rolled-back save.
      applyStockListRowPatch(parentRef, itemId: itemId, patch: patch);
    }
    // Detail overlay no longer matches server state — drop it; the post-save
    // re-sync refetches authoritative detail.
    clearStockItemDetailPatch(parentRef, itemId: itemId);
  }

  static Future<void> _afterSaveBackgroundWithRef({
    required WidgetRef parentRef,
    required String itemId,
    required num parsed,
    required Map<String, dynamic> itemRow,
    required String itemName,
    required String unit,
    required bool refreshItemDetail,
  }) async {
    final reorder = coerceToDouble(itemRow['reorder_level']);
    final crossedReorder = reorder > 0 && parsed <= reorder;
    _resyncStockAfterSave(
      parentRef: parentRef,
      itemId: itemId,
      reorderAlert: crossedReorder,
    );
    if (crossedReorder) {
      final unitLabel = unit.isNotEmpty ? unit.toUpperCase() : '';
      await LocalNotificationsService.instance.showLowStockItem(
        itemName: itemName,
        detail:
            '${formatStockQtyForUnit(unit, parsed.toDouble())} $unitLabel (reorder ${formatStockQtyForUnit(unit, reorder)})',
      );
    }
  }

  /// Reconcile list/detail caches with the server after any save attempt
  /// (success or failure) so the UI converges without a manual refresh.
  static void _resyncStockAfterSave({
    required WidgetRef parentRef,
    required String itemId,
    bool reorderAlert = false,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Always refresh detail + activity history after a system/physical save.
      invalidateStockRowSaveSurfaces(
        parentRef,
        itemId: itemId,
        reorderAlert: reorderAlert,
        refreshItemDetail: true,
      );
      parentRef.invalidate(stockChangesFeedProvider);
      if (itemId.isNotEmpty) {
        parentRef.invalidate(stockItemActivityProvider(itemId));
      }
    });
  }

  /// True when a write may have reached the server even though the client saw an
  /// error (timeout / transport failure). Such writes are NOT rolled back
  /// client-side; the row keeps the optimistic value until the server reconciles.
  static bool _writeOutcomeIsUncertain(Object error) {
    if (error is TimeoutException) return true;
    if (error is DioException) {
      if (error.response != null) return false; // Server answered — definite.
      return dioIsAutoRetryableTransport(error);
    }
    return false;
  }

  static Future<void> _completeStockSaveAfterPop({
    required WidgetRef parentRef,
    required String itemId,
    required StockUpdateMode mode,
    required num parsed,
    required Map<String, dynamic> itemRow,
    required Map<String, dynamic> preSaveSnapshot,
    required String reasonLabel,
    required String? reasonType,
    required String note,
    required int? stockVersion,
    required String itemName,
    required String unit,
    required bool refreshItemDetail,
    required String idempotencyKey,
    ScaffoldMessengerState? messenger,
  }) async {
    try {
      final saved = await _persistStockWithRef(
        parentRef: parentRef,
        itemId: itemId,
        mode: mode,
        parsed: parsed,
        reasonLabel: reasonLabel,
        reasonType: reasonType,
        note: note,
        stockVersion: stockVersion,
        idempotencyKey: idempotencyKey,
      );
      if (saved == null || saved.isEmpty) {
        throw StateError('Could not save stock — sign in again and retry.');
      }
      if (kDebugMode) {
        debugPrint(
          '[STOCK_SAVE_SUCCESS] status=${saved['current_stock'] ?? saved['physical_stock_qty']}',
        );
      }
      _QuickStockActionBodyState._applyOptimisticListPatchStatic(
        parentRef: parentRef,
        itemId: itemId,
        mode: mode,
        itemRow: itemRow,
        saved: saved,
        parsed: parsed,
      );
      parentRef.invalidate(stockStatusCountsProvider);
      emitBusinessWriteEvent(parentRef, kind: 'stock', affectedItemIds: {itemId});
      if (mode == StockUpdateMode.physical) {
        if (kDebugMode) {
          StockApiStormMonitor.flushNow(reason: 'physical_save_ok');
        }
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'Physical saved — system ledger unchanged. Switch to System to update ledger qty.',
            ),
            duration: Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        // System ledger edit — offer 15‑min undo (same as barcode scan path).
        showStockUndoSnackBar(
          messenger: messenger,
          ref: parentRef,
          itemId: itemId,
          itemName: itemName,
        );
      }
      await _afterSaveBackgroundWithRef(
        parentRef: parentRef,
        itemId: itemId,
        parsed: parsed,
        itemRow: itemRow,
        itemName: itemName,
        unit: unit,
        refreshItemDetail: refreshItemDetail,
      );
    } catch (e) {
      if (_writeOutcomeIsUncertain(e)) {
        // The write may have committed server-side (timeout / transport error) —
        // keep the optimistic overlay and reconcile with the server instead of
        // reverting the row to a value the backend no longer has.
        _resyncStockAfterSave(parentRef: parentRef, itemId: itemId);
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'Save is still completing — the stock list will refresh shortly.',
            ),
            duration: Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      _rollbackOptimisticPatchWithRef(
        parentRef: parentRef,
        itemId: itemId,
        preSaveSnapshot: preSaveSnapshot,
      );
      // Even on a definite rejection, reconcile so the row reflects the true
      // server state (e.g. another user's newer value) without a manual refresh.
      _resyncStockAfterSave(parentRef: parentRef, itemId: itemId);
      if (e is StaleStockConflict) {
        try {
          final session = parentRef.read(sessionProvider);
          if (session != null) {
            await parentRef.read(hexaApiProvider).getStockItem(
                  businessId: session.primaryBusiness.id,
                  itemId: itemId,
                );
          }
        } catch (_) {}
      }
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            e is StaleStockConflict
                ? StaleStockConflict.userMessage
                : e is DioException
                    ? friendlyApiError(e)
                    : userFacingError(e),
          ),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static void _applyOptimisticListPatchStatic({
    required WidgetRef parentRef,
    required String itemId,
    required StockUpdateMode mode,
    required Map<String, dynamic> itemRow,
    required Map<String, dynamic>? saved,
    required num parsed,
  }) {
    final system = coerceToDouble(itemRow['current_stock']);
    final reorder = itemRow['reorder_level'];
    var patch = mode == StockUpdateMode.physical
        ? stockListPatchFromPhysicalCount(
            {
              ...?saved,
              if (reorder != null) 'reorder_level': reorder,
            },
            fallbackCountedQty: parsed,
            fallbackSystemQty: system,
          )
        : stockListPatchFromStockDetail(
            {
              ...?saved,
              if (reorder != null) 'reorder_level': reorder,
            },
            fallbackQty: parsed,
          );
    if (patch.isEmpty && mode == StockUpdateMode.physical) {
      final now = DateTime.now().toUtc().toIso8601String();
      patch = {
        'physical_stock_qty': parsed,
        'physical_stock_difference_qty': parsed - system,
        'physical_stock_counted_at': now,
      };
    }
    if (patch.isEmpty && mode == StockUpdateMode.system) {
      patch = _systemOptimisticFallbackStatic(
        parsed: parsed,
        row: itemRow,
      );
    }
    if (patch.isEmpty) return;
    applyStockListRowPatch(parentRef, itemId: itemId, patch: patch);
    applyStockItemDetailPatch(parentRef, itemId: itemId, patch: patch);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!mounted) return;

    if (_itemId.isEmpty) {
      setState(() => _qtyError = 'Item missing — close and try again');
      return;
    }

    if (!_canSave) {
      if (!mounted) return;
      setState(() {
        _qtyError = _qtyErrorText();
        if (_mode == StockUpdateMode.system &&
            (_reasonType == null || _reasonType!.isEmpty)) {
          _reasonError = 'Select a reason';
        }
      });
      return;
    }
    final parsed = _parseEnteredQty();
    if (parsed == null) {
      setState(() => _qtyError = _qtyErrorText());
      return;
    }
    if (_saving) return;
    if (!mounted) return;
    setState(() => _saving = true);
    if (kDebugMode) {
      debugPrint(
        '[STOCK_SAVE_START] itemId=$_itemId mode=$_mode qty=$parsed',
      );
    }
    _preSaveItemSnapshot = Map<String, dynamic>.from(_item);
    final preSaveSnapshot = _preSaveItemSnapshot!;
    final captureItemRow = Map<String, dynamic>.from(_item);
    final captureItemId = _itemId;
    final captureMode = _mode;
    final captureReasonLabel = _reasonLabel;
    final captureReasonType = _reasonType;
    final captureNote = _notesCtrl.text.trim();
    final captureStockVersion = _stockVersion();
    final captureName = _name;
    final captureUnit = _unit;
    final captureRefreshDetail = widget.refreshItemDetail;
    final parentRef = widget.parentRef;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final idempotencyKey =
        'stock-save:$captureItemId:${DateTime.now().microsecondsSinceEpoch}';

    // Patch list immediately so the row updates as the sheet closes.
    try {
      _applyOptimisticListPatch(
        null,
        parsed,
        parentRef: parentRef,
        itemId: captureItemId,
        mode: captureMode,
        itemRow: captureItemRow,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[STOCK_SAVE_PATCH] optimistic patch failed: $e\n$st');
      }
    }
    if (mounted) Navigator.of(context).pop(true);
    unawaited(HapticFeedback.mediumImpact());
    unawaited(
      _completeStockSaveAfterPop(
        parentRef: parentRef,
        itemId: captureItemId,
        mode: captureMode,
        parsed: parsed,
        itemRow: captureItemRow,
        preSaveSnapshot: preSaveSnapshot,
        reasonLabel: captureReasonLabel,
        reasonType: captureReasonType,
        note: captureNote,
        stockVersion: captureStockVersion,
        itemName: captureName,
        unit: captureUnit,
        refreshItemDetail: captureRefreshDetail,
        idempotencyKey: idempotencyKey,
        messenger: messenger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildForm(context);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[STOCK_UPDATE_SHEET] build failed: $e\n$st');
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Could not open stock update',
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
    final canSave = _canSave;
    final systemQty = coerceToDouble(_item['current_stock']);
    final systemSafe = systemQty.isFinite ? systemQty : 0.0;
    final stockLabel = stockDisplayPrimary(_current, _unit);
    final lastPhysical = _lastPhysicalLabel;
    final entered = _parseEnteredQty();
    final liveDiff = _liveDiff;
    final systemAdj = _systemAdjustmentVariance;
    final physQty = _physicalQty;
    final physVsSystem = _physicalVsSystemVariance;
    final history = _historyLabel;
    final desktop = HexaBreakpoints.isDesktop(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Cancel',
              onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            ),
          ],
        ),
        if (_itemCode.isNotEmpty)
          Text(
            'Product code: $_itemCode',
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
        if (_refreshing) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
        if (_refreshError != null) ...[
          const SizedBox(height: 6),
          Text(
            _refreshError!,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFFB45309),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: HexaColors.neutral,
            ),
            children: [
              TextSpan(
                text: _mode == StockUpdateMode.physical
                    ? 'Current physical: '
                    : 'System quantity: ',
              ),
              TextSpan(
                text: _mode == StockUpdateMode.system
                    ? '${formatStockQtyForUnit(_unit, systemSafe)} $_unitLabel'
                    : stockLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _mode == StockUpdateMode.physical
                      ? HexaColors.brandTealMid
                      : HexaDsColors.blue,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        if (_mode == StockUpdateMode.physical) ...[
          const SizedBox(height: 3),
          Text(
            'System (from purchases/delivery): ${formatStockQtyForUnit(_unit, systemSafe)} $_unitLabel (unchanged by this save)',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: HexaColors.neutral,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'Diff = floor remaining − system. Daily edits update Physical only.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: HexaColors.textBody,
            ),
          ),
        ],
        if (_mode == StockUpdateMode.system) ...[
          const SizedBox(height: 3),
          Text(
            physQty == null
                ? 'Physical quantity: — (no count recorded)'
                : 'Physical quantity: ${formatStockQtyForUnit(_unit, physQty)} $_unitLabel',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: HexaColors.brandTealDeep,
            ),
          ),
          if (physVsSystem != null) ...[
            const SizedBox(height: 3),
            Text(
              'Ledger variance (physical − system): '
              '${physVsSystem > 0.001 ? '+' : ''}'
              '${formatStockQtyForUnit(_unit, physVsSystem)} $_unitLabel',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: physVsSystem.abs() < 0.001
                    ? HexaColors.neutral
                    : physVsSystem > 0
                        ? const Color(0xFF15803D)
                        : HexaDsColors.error,
              ),
            ),
          ],
        ],
        if (lastPhysical != null && _mode == StockUpdateMode.physical)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              lastPhysical,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: HexaColors.brandTealDeep,
              ),
            ),
          ),
        if (history != null) ...[
          const SizedBox(height: 4),
          Text(
            history,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: HexaColors.neutral,
            ),
          ),
        ],
        if (_mode == StockUpdateMode.system) ...[
          const SizedBox(height: 6),
          Text(
            _approvalNote,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: HexaColors.textBody,
            ),
          ),
        ],
        const SizedBox(height: 10),
        StockUpdateModeToggle(
          mode: _mode,
          onChanged: _saving ? (_) {} : _onModeChanged,
          allowSystem: widget.allowSystem,
        ),
        const Divider(height: 20),
        AppFormRow(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _mode == StockUpdateMode.system
                      ? 'Entered system quantity'
                      : 'Floor remaining (Physical)',
                  style:
                      const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _qtyCtrl,
                  autofocus: true,
                  enabled: !_saving,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                  ],
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    errorText: _qtyError,
                    suffixText: _unitLabel,
                  ),
                  onSubmitted: (_) {
                    if (canSave) _onSavePressed();
                  },
                ),
              ],
            ),
            if (_mode == StockUpdateMode.physical)
              _DifferenceBanner(
                label: 'Difference',
                emptyHint:
                    'Difference: enter a quantity to compare with system stock',
                entered: entered,
                baselineQty: systemSafe,
                diff: liveDiff,
                unit: _unit,
                unitLabel: _unitLabel,
                baselineName: 'system',
              )
            else
              _DifferenceBanner(
                label: 'Variance',
                emptyHint:
                    'Variance: enter a quantity to see change vs current system stock',
                entered: entered,
                baselineQty: systemSafe,
                diff: systemAdj,
                unit: _unit,
                unitLabel: _unitLabel,
                baselineName: 'current',
              ),
          ],
        ),
        if (_mode == StockUpdateMode.physical) ...[
          const SizedBox(height: 10),
          const Text(
            'Reason',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              avatar: const Icon(Icons.inventory_outlined, size: 16),
              label: Text(
                _reasonLabel.isNotEmpty ? _reasonLabel : 'Physical count',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
        if (_mode == StockUpdateMode.system) ...[
          const SizedBox(height: 14),
          const Text(
            'Reason',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final chip in _kReasonChips)
                HexaAccessibleFilterChip(
                  label: chip.$1,
                  selected: _reasonLabel == chip.$1,
                  onSelected: _saving
                      ? null
                      : (_) => setState(() {
                            _reasonType = chip.$2;
                            _reasonLabel = chip.$1;
                            _reasonError = null;
                          }),
                  compact: true,
                ),
            ],
          ),
          if (_reasonError != null) ...[
            const SizedBox(height: 6),
            Text(
              _reasonError!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: HexaDsColors.error,
              ),
            ),
          ],
        ],
        const SizedBox(height: 14),
        const Text(
          'Notes (optional)',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _notesCtrl,
          enabled: !_saving,
          maxLines: 2,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
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
                child: SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: canSave && !_saving ? _onSavePressed : null,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _mode == StockUpdateMode.system
                                ? 'SAVE SYSTEM STOCK'
                                : 'SAVE PHYSICAL COUNT',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                  ),
                ),
              ),
            ],
          )
        else
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: canSave && !_saving ? _onSavePressed : null,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _mode == StockUpdateMode.system
                          ? 'SAVE SYSTEM STOCK'
                          : 'SAVE PHYSICAL COUNT',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
            ),
          ),
      ],
    );
  }
}

class _DifferenceBanner extends StatelessWidget {
  const _DifferenceBanner({
    required this.label,
    required this.emptyHint,
    required this.entered,
    required this.baselineQty,
    required this.diff,
    required this.unit,
    required this.unitLabel,
    required this.baselineName,
  });

  final String label;
  final String emptyHint;
  final double? entered;
  final double baselineQty;
  final double? diff;
  final String unit;
  final String unitLabel;
  final String baselineName;

  @override
  Widget build(BuildContext context) {
    if (entered == null || diff == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: HexaColors.slate100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: HexaColors.slateBorder),
        ),
        child: Text(
          emptyHint,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: HexaColors.neutral,
          ),
        ),
      );
    }
    final d = diff!;
    final sign = d > 0.001 ? '+' : '';
    final color = d.abs() < 0.001
        ? HexaColors.slate700
        : d > 0
            ? const Color(0xFF15803D)
            : HexaDsColors.error;
    final bg = d.abs() < 0.001
        ? HexaColors.slate100
        : d > 0
            ? HexaDsColors.successSurface
            : const Color(0xFFFEF2F2);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        '$label: $sign${formatStockQtyForUnit(unit, d)} $unitLabel'
        '  (entered ${formatStockQtyForUnit(unit, entered!)} − $baselineName ${formatStockQtyForUnit(unit, baselineQty)})',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
