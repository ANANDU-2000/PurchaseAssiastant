import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/business_aggregates_invalidation.dart';
import '../../core/providers/realtime_events_provider.dart';

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
  DateTime? _lastWarehouseInvalidate;

  bool _throttleWarehouse() {
    final now = DateTime.now();
    if (_lastWarehouseInvalidate != null &&
        now.difference(_lastWarehouseInvalidate!).inSeconds < 45) {
      return true;
    }
    _lastWarehouseInvalidate = now;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeInvalidationProvider, (prev, next) {
      final signal = next.valueOrNull;
      if (signal == null || signal.tick == _lastTick) return;
      _lastTick = signal.tick;
      if (signal.notifications) {
        invalidateNotificationSurfaces(ref);
      }
      if (signal.warehouse) {
        final urgent = signal.affectedItemIds.isNotEmpty;
        if (urgent || !_throttleWarehouse()) {
          final ids = signal.affectedItemIds;
          if (ids.isEmpty) {
            invalidateWarehouseSurfacesLight(ref);
          } else {
            for (final id in ids) {
              invalidateWarehouseSurfacesLight(ref, itemId: id);
            }
          }
        }
      }
    });
    return widget.child;
  }
}
