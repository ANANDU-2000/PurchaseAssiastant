import 'dart:async';

import 'package:flutter/scheduler.dart';

/// Avoid Riverpod "modify provider during build" when listeners react to writes.
void deferInvalidate(dynamic ref, Object provider) {
  SchedulerBinding.instance.addPostFrameCallback((_) {
    ref.invalidate(provider);
  });
}

/// Post-frame invalidate after [delay] — gives DB time to propagate before refetch.
void deferInvalidateDelayed(
  dynamic ref,
  Object provider, {
  Duration delay = const Duration(milliseconds: 1500),
}) {
  SchedulerBinding.instance.addPostFrameCallback((_) {
    Timer(delay, () => ref.invalidate(provider));
  });
}

void deferVoid(void Function() fn) {
  SchedulerBinding.instance.addPostFrameCallback((_) => fn());
}
