/// Single turn in the in-app assistant thread (local + API replay).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.at,
    this.showPreviewActions = false,
    this.draftSnapshot,
  });

  final String id;
  final String text;
  final bool isUser;
  final DateTime at;
  final bool showPreviewActions;
  final Map<String, dynamic>? draftSnapshot;
}
