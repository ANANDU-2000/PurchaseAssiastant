import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../assistant_chat_theme.dart';

/// Hold-to-speak mic button with pulse + glow while listening.
class MicButton extends StatefulWidget {
  const MicButton({
    super.key,
    required this.listening,
    required this.onStart,
    required this.onStop,
    this.enabled = true,
    this.onUnavailableTap,
  });

  final bool listening;
  final VoidCallback onStart;
  final VoidCallback onStop;
  /// When false (e.g. speech engine failed to init), show mic but do not start listen.
  final bool enabled;
  /// Short tap when [enabled] is false (e.g. explain permissions).
  final VoidCallback? onUnavailableTap;

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (widget.listening) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant MicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listening == widget.listening) return;
    if (widget.listening) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tip = widget.enabled
        ? 'Hold to speak (Malayalam or English)'
        : 'Voice unavailable — check microphone permission in Settings';
    final core = Tooltip(
      message: tip,
      child: GestureDetector(
        onLongPressStart: (_) {
          if (!widget.enabled) return;
          HapticFeedback.mediumImpact();
          widget.onStart();
        },
        onLongPressEnd: (_) {
          if (!widget.enabled) return;
          widget.onStop();
        },
        onLongPressCancel: () {
          if (!widget.enabled) return;
          widget.onStop();
        },
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final scale = widget.listening ? (1 + (_pulse.value * 0.2)) : 1.0;
            return Transform.scale(scale: scale, child: child);
          },
          child: AnimatedContainer(
            duration: AssistantChatTheme.shortAnim,
            curve: AssistantChatTheme.motion,
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: !widget.enabled
                  ? const Color(0xFFE8E8E8)
                  : widget.listening
                      ? const Color(0xFFE53935)
                      : const Color(0xFFE5E7EB),
              boxShadow: widget.listening && widget.enabled
                  ? [
                      BoxShadow(
                        color: const Color(0xFFE53935).withValues(alpha: 0.45),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Icon(
              widget.listening ? Icons.stop_rounded : Icons.mic_rounded,
              color: widget.listening
                  ? Colors.white
                  : (!widget.enabled ? Colors.black38 : Colors.black54),
              size: 22,
            ),
          ),
        ),
      ),
    );
    if (!widget.enabled && widget.onUnavailableTap != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onUnavailableTap,
        child: core,
      );
    }
    return core;
  }
}
