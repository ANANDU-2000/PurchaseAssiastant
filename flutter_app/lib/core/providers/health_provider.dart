import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';

/// Polls `/health`. Use `intent_llm_active` for real LLM intent (groq/openai/gemini + key); `ai_status` is llm_ready | rules_only | missing_api_key.
final healthProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.watch(hexaApiProvider);
  return api.health();
});
