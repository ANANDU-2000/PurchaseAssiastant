import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/provider_api_guard.dart' show safeRefOnDispose;

/// Creates a [CancelToken] tied to the provider lifecycle.
///
/// Automatically cancels the token when the provider is disposed, preventing
/// wasted bandwidth from in-flight requests after navigation away.
CancelToken registerCancelToken(dynamic ref) {
  final token = CancelToken();
  safeRefOnDispose(ref, () {
    if (!token.isCancelled) token.cancel('provider_disposed');
  });
  return token;
}

/// Executes [fetch] and returns the result, using a cancellation-aware
/// [CancelToken] and an optional [timeout].
///
/// Usage inside a provider:
/// ```dart
/// final result = await cancellableFetch(
///   ref,
///   () => api.someEndpoint(...),
///   timeout: const Duration(seconds: 15),
/// );
/// ```
Future<T> cancellableFetch<T>(
  dynamic ref,
  Future<T> Function(CancelToken token) fetch, {
  Duration? timeout,
}) async {
  final token = registerCancelToken(ref);
  var future = fetch(token);
  if (timeout != null) {
    future = future.timeout(timeout);
  }
  return future;
}

/// Returns the previous value of an [AsyncValue] before the latest refresh.
///
/// Useful for stale-while-revalidate: serve the old data while the new fetch
/// is in progress.
T? previousValue<T>(Ref ref, ProviderBase<AsyncValue<T>> provider) {
  try {
    final current = ref.read(provider);
    return current.valueOrNull;
  } catch (_) {
    return null;
  }
}
