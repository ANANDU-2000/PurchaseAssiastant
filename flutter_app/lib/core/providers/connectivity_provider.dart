import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits connectivity updates; use to show offline banner (core flows may still read cached data).
final connectivityResultsProvider =
    StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

bool isOfflineResult(List<ConnectivityResult>? results) {
  if (results == null || results.isEmpty) return true;
  return results.every((r) => r == ConnectivityResult.none);
}
