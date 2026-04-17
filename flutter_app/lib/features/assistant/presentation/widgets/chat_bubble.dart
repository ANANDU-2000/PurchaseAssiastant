import 'dart:async';

import 'package:flutter/material.dart';

import '../assistant_chat_theme.dart';

class ChatBubble extends StatefulWidget {
  const ChatBubble({
    super.key,
    required this.text,
    required this.isUser,
    required this.time,
    this.animateEntrance = true,
    this.typewriter = false,
    /// When false, timestamp + read receipts are hidden (message grouping).
    this.showMeta = true,
    this.tightGroupTop = false,
    this.onLongPress,
    this.onSwipeReply,
    this.replySnippet,
    this.onTypewriterComplete,
  });

  final String text;
  final bool isUser;
  final DateTime time;
  final bool animateEntrance;
  final bool typewriter;
  final bool showMeta;
  final bool tightGroupTop;
  final void Function(String text, bool isUser)? onLongPress;
  final VoidCallback? onSwipeReply;
  final String? replySnippet;
  final VoidCallback? onTypewriterComplete;

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  String _shown = '';
  Timer? _tw;
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: AssistantChatTheme.mediumAnim,
    );
    if (widget.animateEntrance) {
      _entrance.forward();
    } else {
      _entrance.value = 1;
    }
    if (widget.typewriter && !widget.isUser) {
      if (widget.text.isEmpty) {
        _shown = '';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onTypewriterComplete?.call();
        });
      } else {
        _shown = '';
        _tw = Timer.periodic(const Duration(milliseconds: 18), (t) {
          if (!mounted) return;
          if (_idx >= widget.text.length) {
            t.cancel();
            setState(() => _shown = widget.text);
            widget.onTypewriterComplete?.call();
            return;
          }
          _idx += widget.text.length > 400 ? 3 : 1;
          setState(() {
            _shown = widget.text.substring(0, _idx.clamp(0, widget.text.length));
          });
        });
      }
    } else {
      _shown = widget.text;
    }
  }

  @override
  void didUpdateWidget(covariant ChatBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text && !widget.typewriter) {
      _shown = widget.text;
    }
  }

  @override
  void dispose() {
    _tw?.cancel();
    _entrance.dispose();
    super.dispose();
  }

  String _timeLabel() {
    final t = TimeOfDay.fromDateTime(widget.time);
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'am' : 'pm';
    return '$h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width * 0.78;
    const r = 18.0;

    final body = AnimatedBuilder(
      animation: _entrance,
      builder: (context, child) {
        final v = Curves.easeOutCubic.transform(_entrance.value);
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(widget.isUser ? 14 * (1 - v) : -14 * (1 - v), 0),
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onHorizontalDragEnd: (d) {
          final vx = d.velocity.pixelsPerSecond.dx;
          if (widget.isUser && vx > 200) widget.onSwipeReply?.call();
          if (!widget.isUser && vx < -200) widget.onSwipeReply?.call();
        },
        onLongPress: widget.onLongPress == null
            ? null
            : () => widget.onLongPress!(
                  _shown.isEmpty ? widget.text : _shown,
                  widget.isUser,
                ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              constraints: BoxConstraints(maxWidth: maxW),
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              decoration: BoxDecoration(
                color: widget.isUser ? AssistantChatTheme.bubbleUser : AssistantChatTheme.bubbleAi,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(r),
                  topRight: const Radius.circular(r),
                  bottomLeft: Radius.circular(widget.isUser ? r : 5),
                  bottomRight: Radius.circular(widget.isUser ? 5 : r),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 14,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(
                  color: widget.isUser
                      ? const Color(0x22075E54)
                      : AssistantChatTheme.bubbleAiBorder,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.replySnippet != null && widget.replySnippet!.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: const Border(
                          left: BorderSide(color: AssistantChatTheme.accent, width: 3),
                        ),
                      ),
                      child: Text(
                        widget.replySnippet!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AssistantChatTheme.inter(12, c: const Color(0xFF667781)),
                      ),
                    ),
                  ],
                  SelectableText(
                    _shown.isEmpty ? widget.text : _shown,
                    style: AssistantChatTheme.inter(
                      14.5,
                      w: FontWeight.w500,
                      c: const Color(0xFF111B21),
                      h: 1.35,
                    ),
                  ),
                  if (widget.showMeta) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _timeLabel(),
                            style: AssistantChatTheme.inter(
                              11,
                              w: FontWeight.w500,
                              c: const Color(0xFF8696A0),
                            ),
                          ),
                          if (widget.isUser) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.done_all_rounded,
                              size: 16,
                              color: AssistantChatTheme.accent.withValues(alpha: 0.95),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              bottom: 2,
              left: widget.isUser ? null : -3,
              right: widget.isUser ? -3 : null,
              child: Transform.rotate(
                angle: widget.isUser ? 0.65 : -0.65,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: widget.isUser ? AssistantChatTheme.bubbleUser : AssistantChatTheme.bubbleAi,
                    border: Border.all(
                      color: widget.isUser
                          ? const Color(0x22075E54)
                          : AssistantChatTheme.bubbleAiBorder,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Align(
      alignment: widget.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(top: widget.tightGroupTop ? 2 : 4, bottom: 6),
        child: body,
      ),
    );
  }
}
