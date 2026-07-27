import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/provider_api_guard.dart';

/// Invalidate immediately (same frame) — use for user-initiated saves where
/// the widget tree has already been disposed (sheet popped) so no build conflict.
void invalidateImmediate(dynamic ref, ProviderOrFamily provider) {
  try {
    resolveInvalidationContainer(ref).invalidate(provider);
  } catch (_) {}
}

/// Avoid Riverpod "modify provider during build" when listeners react to writes.
void deferInvalidate(dynamic ref, ProviderOrFamily provider) {
  SchedulerBinding.instance.addPostFrameCallback((_) {
    try {
      resolveInvalidationContainer(ref).invalidate(provider);
    } catch (_) {}
  });
}

/// Post-frame invalidate after [delay] — gives DB time to propagate before refetch.
void deferInvalidateDelayed(
  dynamic ref,
  ProviderOrFamily provider, {
  Duration delay = const Duration(milliseconds: 400),
}) {
  SchedulerBinding.instance.addPostFrameCallback((_) {
    ProviderContainer container;
    try {
      container = resolveInvalidationContainer(ref);
    } catch (_) {
      return;
    }
    Timer(delay, () {
      try {
        container.invalidate(provider);
      } catch (_) {}
    });
  });
}

void deferVoid(void Function() fn) {
  SchedulerBinding.instance.addPostFrameCallback((_) => fn());
}
