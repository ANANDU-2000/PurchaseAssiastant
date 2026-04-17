import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../assistant_chat_theme.dart';
import 'mic_button.dart';
import 'send_button.dart';

/// Modern WhatsApp-style composer with mic/send switch.
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    this.focusNode,
    required this.onSend,
    required this.loading,
    this.speechReady = false,
    this.listening = false,
    this.onMicDown,
    this.onMicUp,
    this.onMicCancel,
    this.replySnippet,
    this.onDismissReply,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback onSend;
  final bool loading;
  final bool speechReady;
  final bool listening;
  final VoidCallback? onMicDown;
  final VoidCallback? onMicUp;
  final VoidCallback? onMicCancel;
  final String? replySnippet;
  final VoidCallback? onDismissReply;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

/// Backward-compatible alias used by existing page code.
class InputBar extends ChatInputBar {
  const InputBar({
    super.key,
    required super.controller,
    super.focusNode,
    required super.onSend,
    required super.loading,
    super.speechReady,
    super.listening,
    super.onMicDown,
    super.onMicUp,
    super.onMicCancel,
    super.replySnippet,
    super.onDismissReply,
  });
}

class _ChatInputBarState extends State<ChatInputBar> {
  void _onCtrl() => setState(() {});
  void _onFocus() => setState(() {});

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onCtrl);
    widget.focusNode?.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onCtrl);
      widget.controller.addListener(_onCtrl);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocus);
      widget.focusNode?.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCtrl);
    widget.focusNode?.removeListener(_onFocus);
    super.dispose();
  }

  bool get _hasText => widget.controller.text.trim().isNotEmpty;
  bool get _isFocused => widget.focusNode?.hasFocus ?? false;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 8, 12, 10 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.replySnippet != null && widget.replySnippet!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AssistantChatTheme.accent.withValues(alpha: 0.35)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.reply_rounded, color: AssistantChatTheme.primary, size: 22),
                    title: Text(
                      widget.replySnippet!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AssistantChatTheme.inter(13, w: FontWeight.w500),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: widget.onDismissReply,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
                color: const Color(0xFFF0F2F5),
                border: Border.all(
                  color: _isFocused
                      ? AssistantChatTheme.accent.withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.7),
                  width: _isFocused ? 1.2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Emoji',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {},
                        icon: const Icon(
                          Icons.sentiment_satisfied_alt_rounded,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      if (widget.listening)
                        Padding(
                          padding: const EdgeInsets.only(left: 2, right: 4, bottom: 10),
                          child: Icon(
                            Icons.graphic_eq_rounded,
                            color: const Color(0xFFE53935).withValues(alpha: 0.9),
                            size: 18,
                          ),
                        ),
                      Expanded(
                        child: TextField(
                          controller: widget.controller,
                          focusNode: widget.focusNode,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) {
                            if (!widget.loading) widget.onSend();
                          },
                          style: AssistantChatTheme.inter(14.5, w: FontWeight.w500),
                          decoration: InputDecoration(
                            hintText: widget.listening ? 'Listening…' : 'Message…',
                            hintStyle: AssistantChatTheme.inter(14.5, c: const Color(0xFF8696A0)),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: AssistantChatTheme.shortAnim,
                        switchInCurve: AssistantChatTheme.motion,
                        switchOutCurve: AssistantChatTheme.motion,
                        transitionBuilder: (c, anim) {
                          return ScaleTransition(
                            scale: anim,
                            child: FadeTransition(opacity: anim, child: c),
                          );
                        },
                        child: _TrailingAction(
                          key: ValueKey('${_hasText}_${widget.listening}'),
                          hasText: _hasText,
                          loading: widget.loading,
                          speechReady: widget.speechReady && !kIsWeb,
                          listening: widget.listening,
                          onMicDown: widget.onMicDown,
                          onMicUp: widget.onMicUp,
                          onMicCancel: widget.onMicCancel,
                          onSend: widget.onSend,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrailingAction extends StatelessWidget {
  const _TrailingAction({
    super.key,
    required this.hasText,
    required this.loading,
    required this.speechReady,
    required this.listening,
    this.onMicDown,
    this.onMicUp,
    this.onMicCancel,
    required this.onSend,
  });

  final bool hasText;
  final bool loading;
  final bool speechReady;
  final bool listening;
  final VoidCallback? onMicDown;
  final VoidCallback? onMicUp;
  final VoidCallback? onMicCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    if (hasText) {
      return Padding(
        padding: const EdgeInsets.only(right: 4, bottom: 2),
        child: SendButton(
          loading: loading,
          onPressed: onSend,
        ),
      );
    }
    if (speechReady) {
      return Padding(
        padding: const EdgeInsets.only(right: 4, bottom: 2),
        child: MicButton(
          listening: listening,
          onStart: onMicDown ?? () {},
          onStop: onMicUp ?? () {},
          onCancel: onMicCancel ?? () {},
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 2),
      child: IconButton(
        onPressed: loading ? null : onSend,
        icon: const Icon(Icons.send_rounded, color: AssistantChatTheme.primary),
      ),
    );
  }
}
