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
      label: 'Profit',
      goLocation: '/reports',
      usePush: true,
    ),
    AssistantQuickPrompt(
      label: 'New purchase',
      goLocation: '/purchase/new',
      usePush: true,
    ),
    AssistantQuickPrompt(
      label: 'Today',
      goLocation: '/analytics',
    ),
    AssistantQuickPrompt(
      label: 'Suppliers',
      goLocation: '/search?section=suppliers',
      usePush: true,
    ),
  ];
});
