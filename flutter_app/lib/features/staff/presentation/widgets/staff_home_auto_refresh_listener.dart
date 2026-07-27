import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/provider_api_guard.dart';
import '../../../../core/platform/app_foreground_provider.dart';
import '../../../../core/providers/realtime_events_provider.dart';
import '../../../../core/providers/staff_home_providers.dart';

/// Keeps staff home KPIs fresh without manual pull-to-refresh.
class StaffHomeAutoRefreshListener extends ConsumerStatefulWidget {
  const StaffHomeAutoRefreshListener({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  ConsumerState<StaffHomeAutoRefreshListener> createState() =>
      _StaffHomeAutoRefreshListenerState();
}

class _StaffHomeAutoRefreshListenerState
    extends ConsumerState<StaffHomeAutoRefreshListener> {
  Timer? _periodic;
  int _lastRealtimeTick = 0;
  DateTime? _lastLightRefresh;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _periodic = Timer.periodic(const Duration(minutes: 2), (_) {
        _refreshLight(reason: 'periodic');
      });
    }
  }

  @override
  void dispose() {
    _periodic?.cancel();
    super.dispose();
  }

  void _refreshLight({required String reason}) {
    if (!mounted || !widget.enabled || providerSkipApi(ref)) return;
    final now = DateTime.now();
    if (_lastLightRefresh != null &&
        now.difference(_lastLightRefresh!) < const Duration(seconds: 25)) {
      return;
    }
    _lastLightRefresh = now;
    invalidateStaffHomeSurfacesLight(ref);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.enabled) {
      ref.listen<DateTime?>(appLastForegroundAtProvider, (prev, next) {
        if (next == null || next == prev) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _refreshLight(reason: 'foreground');
        });
      });

      ref.listen<AsyncValue<RealtimeInvalidationSignal>>(
        realtimeInvalidationProvider,
        (prev, next) {
        final signal = next.valueOrNull;
        if (signal == null || signal.tick == _lastRealtimeTick) return;
        if (!signal.delivery && !signal.warehouse && !signal.notifications) {
          return;
        }
        _lastRealtimeTick = signal.tick;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _refreshLight(reason: 'realtime');
        });
      });
    }
    return widget.child;
  }
}
