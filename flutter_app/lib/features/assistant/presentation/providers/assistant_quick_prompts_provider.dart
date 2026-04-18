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
    AssistantQuickPrompt(label: 'Profit', message: 'Profit this month'),
    AssistantQuickPrompt(
      label: 'New purchase',
      message: 'Help me add a purchase: item, qty, buy price',
    ),
    AssistantQuickPrompt(label: 'Today', message: 'Summary today'),
    AssistantQuickPrompt(label: 'Suppliers', message: 'Show suppliers summary'),
  ];
});
