import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../assistant_chat_theme.dart';
import 'mic_button.dart';

/// Floating glass-style composer with mic / send.
class InputBar extends StatefulWidget {
  const InputBar({
    super.key,
    required this.controller,
    this.focusNode,
    required this.onSend,
    required this.loading,
    this.speechReady = false,
    this.listening = false,
    this.onMicDown,
    this.onMicUp,
    this.replySnippet,
    this.onDismissReply,
    this.speechLocaleLabel = 'ML',
    this.showLocaleToggle = false,
    this.onLocaleToggle,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback onSend;
  final bool loading;
  final bool speechReady;
  final bool listening;
  final VoidCallback? onMicDown;
  final VoidCallback? onMicUp;
  final String? replySnippet;
  final VoidCallback? onDismissReply;
  final String speechLocaleLabel;
  final bool showLocaleToggle;
  final VoidCallback? onLocaleToggle;

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  void _onCtrl() => setState(() {});

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onCtrl);
  }

  @override
  void didUpdateWidget(covariant InputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onCtrl);
      widget.controller.addListener(_onCtrl);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCtrl);
    super.dispose();
  }

  bool get _hasText => widget.controller.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.fromLTRB(10, 6, 10, 8 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.replySnippet != null && widget.replySnippet!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AssistantChatTheme.accent.withValues(alpha: 0.35)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
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
                    color: Colors.black.withValues(alpha: 0.09),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
                color: const Color(0xFFF0F2F5),
                border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (widget.listening)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, right: 6, bottom: 10),
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
                          style: AssistantChatTheme.inter(15, w: FontWeight.w500),
                          decoration: InputDecoration(
                            hintText: widget.listening ? 'Listening…' : 'Message…',
                            hintStyle: AssistantChatTheme.inter(15, c: const Color(0xFF8696A0)),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                          key: ValueKey('${_hasText}_${widget.listening}_${widget.speechReady}'),
                          hasText: _hasText,
                          loading: widget.loading,
                          voiceUiEnabled: !kIsWeb,
                          speechReady: widget.speechReady,
                          listening: widget.listening,
                          onMicDown: widget.onMicDown,
                          onMicUp: widget.onMicUp,
                          onSend: widget.onSend,
                          speechLocaleLabel: widget.speechLocaleLabel,
                          showLocaleToggle: widget.showLocaleToggle,
                          onLocaleToggle: widget.onLocaleToggle,
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
    required this.voiceUiEnabled,
    required this.speechReady,
    required this.listening,
    this.onMicDown,
    this.onMicUp,
    required this.onSend,
    this.speechLocaleLabel = 'ML',
    this.showLocaleToggle = false,
    this.onLocaleToggle,
  });

  final bool hasText;
  final bool loading;
  /// Show mic row on iOS/Android (false on web build).
  final bool voiceUiEnabled;
  /// Speech engine initialized and permission OK.
  final bool speechReady;
  final bool listening;
  final VoidCallback? onMicDown;
  final VoidCallback? onMicUp;
  final VoidCallback onSend;
  final String speechLocaleLabel;
  final bool showLocaleToggle;
  final VoidCallback? onLocaleToggle;

  @override
  Widget build(BuildContext context) {
    Widget sendFab() => FilledButton(
          onPressed: loading ? null : onSend,
          style: FilledButton.styleFrom(
            backgroundColor: AssistantChatTheme.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.all(12),
            minimumSize: const Size(48, 48),
            shape: const CircleBorder(),
            elevation: 0,
          ),
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                )
              : const Icon(Icons.send_rounded, size: 22),
        );

    if (!voiceUiEnabled) {
      return Padding(
        padding: const EdgeInsets.only(right: 4, bottom: 2),
        child: sendFab(),
      );
    }

    void explainVoiceOff() {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Voice is off. Allow Microphone (and Speech recognition) in phone Settings, then return here.',
          ),
        ),
      );
    }

    Widget? localeChip() {
      if (!showLocaleToggle || onLocaleToggle == null) return null;
      return GestureDetector(
        onTap: speechReady ? onLocaleToggle : explainVoiceOff,
        child: Opacity(
          opacity: speechReady ? 1 : 0.5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: speechLocaleLabel == 'ML'
                  ? const Color(0xFF075E54)
                  : const Color(0xFFEEEEEE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              speechLocaleLabel,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: speechLocaleLabel == 'ML'
                    ? Colors.white
                    : Colors.grey.shade700,
              ),
            ),
          ),
        ),
      );
    }

    final mic = MicButton(
      listening: listening,
      enabled: speechReady,
      onUnavailableTap: explainVoiceOff,
      onStart: onMicDown ?? () {},
      onStop: onMicUp ?? () {},
    );

    final lc = localeChip();
    if (hasText) {
      return Padding(
        padding: const EdgeInsets.only(right: 4, bottom: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (lc != null) lc,
            mic,
            const SizedBox(width: 6),
            sendFab(),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (lc != null) lc,
          mic,
        ],
      ),
    );
  }
}
