import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Smart suggestion: label shown on chip → full text sent to the assistant.
class AssistantQuickPrompt {
  const AssistantQuickPrompt({required this.label, required this.message});

  final String label;
  final String message;
}

/// Static prompt list (Riverpod so the bar can `watch` / test overrides).
final assistantQuickPromptsProvider = Provider<List<AssistantQuickPrompt>>((ref) {
  return const [
    AssistantQuickPrompt(label: 'Profit this month', message: 'Profit this month'),
    AssistantQuickPrompt(
      label: 'Add purchase',
      message: 'Help me add a purchase: item, qty, buy price',
    ),
    AssistantQuickPrompt(label: 'New supplier', message: 'Create supplier '),
    AssistantQuickPrompt(label: 'Today', message: 'Summary today'),
  ];
});
