/// Single turn in the in-app assistant thread (local + API replay).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.at,
    this.showPreviewActions = false,
    this.draftSnapshot,
    this.intent,
    this.missingItems,
  });

  final String id;
  final String text;
  final bool isUser;
  final DateTime at;
  final bool showPreviewActions;
  final Map<String, dynamic>? draftSnapshot;
  /// Server intent for this turn (e.g. `clarify_items`, `add_purchase_preview`).
  final String? intent;
  /// Lines that need catalog resolution before save (`clarify_items`).
  final List<Map<String, dynamic>>? missingItems;
}
