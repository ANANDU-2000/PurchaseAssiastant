import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Smart chip: optional in-app navigation plus optional message to the assistant.
class AssistantQuickPrompt {
  const AssistantQuickPrompt({
    required this.label,
    this.message,
    this.goLocation,
    this.usePush = false,
  });

  final String label;
  final String? message;
  /// When set, opens this path (`context.go` unless [usePush] is true).
  final String? goLocation;
  final bool usePush;
}

/// Static prompt list (Riverpod so the bar can `watch` / test overrides).
final assistantQuickPromptsProvider = Provider<List<AssistantQuickPrompt>>((ref) {
  return const [
    AssistantQuickPrompt(
      label: '+ Purchase',
      message: 'New purchase',
    ),
    AssistantQuickPrompt(
      label: 'Profit',
      message: "What's my profit this month?",
    ),
    AssistantQuickPrompt(
      label: 'Pending',
      message: 'Show pending deliveries',
    ),
    AssistantQuickPrompt(
      label: 'Top Items',
      message: 'Top items this month',
    ),
    AssistantQuickPrompt(
      label: 'Suppliers',
      message: 'List active suppliers this month',
    ),
  ];
});
