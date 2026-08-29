import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/provider_api_guard.dart';
import '../../core/providers/business_aggregates_invalidation.dart'
    show
        stockWriteCoordinator,
        invalidateNotificationSurfaces,
        invalidateStaffDeliverySurfacesLight,
        invalidateWarehouseSurfacesLight,
        invalidateWarehouseItemSurfacesLight;
import '../../core/providers/business_write_revision.dart'
    show
        bumpRemoteBusinessDataRevision,
        markWarehouseGlobalInvalidated,
        warehouseGlobalInvalidateRecently;
import '../../core/providers/stock_providers.dart' show patchStockItemInCache;
import '../../core/providers/home_owner_dashboard_providers.dart'
    show homeInventorySummaryProvider, homeRecentActivityFeedProvider;
import '../../core/providers/realtime_events_provider.dart';

/// Coalesce window for warehouse fan-out after realtime signals.
const Duration kRealtimeWarehouseCoalesce = Duration(seconds: 8);

/// Single shell-level realtime fan-out (not tied to Home tab mount).
class ShellRealtimeListener extends ConsumerStatefulWidget {
  const ShellRealtimeListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ShellRealtimeListener> createState() =>
      _ShellRealtimeListenerState();
}

class _ShellRealtimeListenerState extends ConsumerState<ShellRealtimeListener> {
  int _lastTick = 0;
  Timer? _warehouseDebounce;
  RealtimeInvalidationSignal? _pendingWarehouseSignal;

  @override
  void dispose() {
    _warehouseDebounce?.cancel();
    super.dispose();
  }

  RealtimeInvalidationSignal _mergeWarehouse(
    RealtimeInvalidationSignal? prev,
    RealtimeInvalidationSignal next,
  ) {
    if (prev == null) return next;
    return RealtimeInvalidationSignal(
      tick: next.tick,
      notifications: prev.notifications || next.notifications,
      warehouse: prev.warehouse || next.warehouse,
      delivery: prev.delivery || next.delivery,
      affectedItemIds: {...prev.affectedItemIds, ...next.affectedItemIds},
    );
  }

  void _scheduleWarehouseInvalidate(RealtimeInvalidationSignal signal) {
    _pendingWarehouseSignal = _mergeWarehouse(_pendingWarehouseSignal, signal);
    // Leading edge: start one timer; later signals merge until it fires.
    _warehouseDebounce ??= Timer(kRealtimeWarehouseCoalesce, () {
      _warehouseDebounce = null;
      if (!mounted || providerSkipApi(ref)) return;
      final pending = _pendingWarehouseSignal;
      _pendingWarehouseSignal = null;
      if (pending == null || !pending.warehouse) return;
      _applyWarehouseSignal(pending);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeInvalidationProvider, (prev, next) {
      final signal = next.valueOrNull;
      if (signal == null || signal.tick == _lastTick) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || providerSkipApi(ref)) return;
        if (signal.tick == _lastTick) return;
        _lastTick = signal.tick;
        _applyRealtimeSignal(signal);
      });
    });
    return widget.child;
  }

  void _applyRealtimeSignal(RealtimeInvalidationSignal signal) {
    if (signal.notifications) {
      invalidateNotificationSurfaces(ref);
    }
    if (signal.delivery) {
      invalidateStaffDeliverySurfacesLight(ref);
    }
    if (signal.warehouse) {
      _scheduleWarehouseInvalidate(signal);
    }
    final singleItemWarehouseOnly = signal.warehouse &&
        !signal.notifications &&
        !signal.delivery &&
        signal.affectedItemIds.length == 1;
    if (!singleItemWarehouseOnly &&
        (signal.notifications || signal.delivery || signal.warehouse)) {
      bumpRemoteBusinessDataRevision(ref);
    }
  }

  void _applyWarehouseSignal(RealtimeInvalidationSignal signal) {
    if (warehouseGlobalInvalidateRecently(ref)) {
      if (kDebugMode) {
        debugPrint('[STOCK_STORM] REALTIME_WAREHOUSE throttled (global recently invalidated)');
      }
      return;
    }
    markWarehouseGlobalInvalidated(ref);
    final ids = signal.affectedItemIds.where((id) => id.isNotEmpty).toSet();
    if (kDebugMode) {
      debugPrint('[STOCK_STORM] REALTIME_WAREHOUSE ids=$ids → ${ids.length == 1 ? 'patchStockItemInCache + coordinator' : 'invalidateWarehouseSurfacesLight + coordinator per-item'}');
    }
    if (ids.length == 1) {
      final id = ids.first;
      unawaited(patchStockItemInCache(ref, itemId: id));
      invalidateWarehouseItemSurfacesLight(ref, itemId: id);
      // Delegate list invalidation to coordinator (deferred, deduped)
      stockWriteCoordinator.noteRealtimeUpdate(ref, id);
    } else {
      invalidateWarehouseSurfacesLight(ref, forRealtimePoll: true);
      for (final id in ids) {
        invalidateWarehouseItemSurfacesLight(ref, itemId: id);
        stockWriteCoordinator.noteRealtimeUpdate(ref, id);
      }
    }
    ref.invalidate(homeRecentActivityFeedProvider);
    ref.invalidate(homeInventorySummaryProvider);
  }
}
