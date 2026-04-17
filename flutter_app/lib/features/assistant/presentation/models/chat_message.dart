enum MessageType { text, audio }

/// Single turn in the in-app assistant thread (local + API replay).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.isUser,
    required this.at,
    this.type = MessageType.text,
    this.text = '',
    this.audioPath,
    this.audioDuration = Duration.zero,
    this.waveform = const [],
    this.showPreviewActions = false,
    this.draftSnapshot,
  }) : assert(
          type == MessageType.text || (audioPath != null && audioPath != ''),
          'audio messages must include audioPath',
        );

  final String id;
  final bool isUser;
  final DateTime at;
  final MessageType type;
  final String text;
  final String? audioPath;
  final Duration audioDuration;
  final List<double> waveform;
  final bool showPreviewActions;
  final Map<String, dynamic>? draftSnapshot;
}
