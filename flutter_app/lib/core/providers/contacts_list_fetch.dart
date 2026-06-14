import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_failure_policy.dart';
import '../auth/provider_api_guard.dart';
import 'stock_list_exceptions.dart';

/// Suppliers/brokers lists — wait for resume JWT gate, retry once on Dio auth_blocked.
Future<List<Map<String, dynamic>>> fetchContactsListWithApiGuard(
  Ref ref,
  Future<List<Map<String, dynamic>>> Function() fetch,
) async {
  await awaitProviderApiReady(ref);
  if (providerSkipApi(ref)) {
    final canForceLiveOnWeb = kIsWeb &&
        !ref.read(auth401CircuitOpenProvider) &&
        !ref.read(authSessionExpiredProvider);
    if (!canForceLiveOnWeb) {
      throw const StockListFetchBlockedException('api_gate');
    }
  }
  try {
    return await fetch();
  } on DioException catch (e) {
    if (e.message == 'auth_blocked') {
      await awaitProviderApiReady(ref, maxWait: const Duration(seconds: 4));
      if (!providerSkipApi(ref)) {
        return await fetch();
      }
      throw const StockListFetchBlockedException('api_gate');
    }
    rethrow;
  }
}
