import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';

/// Polls `/health` for ops; [aiStatusOk] is true when server reports `ai_ready` (stub or keys set).
final healthProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.watch(hexaApiProvider);
  return api.health();
});
