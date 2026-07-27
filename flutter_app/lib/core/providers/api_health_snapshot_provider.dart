import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/hexa_api.dart';
import '../auth/provider_api_guard.dart';
import '../auth/session_notifier.dart' show hexaApiProvider;

/// Cached `/health/live` + `/health/ready` probes — one inflight per session boot.
class ApiHealthSnapshot {
  const ApiHealthSnapshot({
    this.live,
    this.ready,
  });

  final Map<String, dynamic>? live;
  final Map<String, dynamic>? ready;

  bool get liveOk => live != null;
  bool get readyOk => ready != null;
}

Future<ApiHealthSnapshot>? _healthInflight;

/// SSOT for health probes — avoids duplicate live/ready XHR from home, stock, main.
final apiHealthSnapshotProvider =
    FutureProvider.autoDispose<ApiHealthSnapshot>((ref) async {
  if (providerSkipApi(ref)) {
    return const ApiHealthSnapshot();
  }
  final api = ref.read(hexaApiProvider);
  if (_healthInflight != null) {
    return _healthInflight!;
  }
  _healthInflight = _loadHealth(api).whenComplete(() {
    _healthInflight = null;
  });
  return _healthInflight!;
});

Future<ApiHealthSnapshot> _loadHealth(HexaApi api) async {
  Map<String, dynamic>? live;
  Map<String, dynamic>? ready;
  try {
    live = await api.healthLive().timeout(const Duration(seconds: 12));
  } catch (_) {}
  try {
    ready = await api.healthReady().timeout(const Duration(seconds: 15));
  } catch (_) {}
  return ApiHealthSnapshot(live: live, ready: ready);
}

/// Convenience: probe live only (reuses [apiHealthSnapshotProvider] inflight).
Future<void> pingApiHealthLive(WidgetRef ref) async {
  await ref.read(apiHealthSnapshotProvider.future);
}

/// Convenience: probe ready (reuses bundle).
Future<bool> pingApiHealthReady(WidgetRef ref) async {
  final snap = await ref.read(apiHealthSnapshotProvider.future);
  return snap.readyOk;
}
