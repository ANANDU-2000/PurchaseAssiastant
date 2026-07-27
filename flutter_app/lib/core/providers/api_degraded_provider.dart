import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global API degradation hint (503 / DB-unavailable / transient network).
/// Cleared on successful `/v1/businesses/...` responses.
class ApiDegradedNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void notifyDegraded([String? message]) {
    state = message ?? 'Cloud sync delayed — showing saved data';
  }

  void clear() => state = null;
}

final apiDegradedProvider =
    NotifierProvider<ApiDegradedNotifier, String?>(ApiDegradedNotifier.new);
