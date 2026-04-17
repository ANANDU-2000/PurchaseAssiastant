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
    required this.onCancel,
  });

  final bool listening;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _cancelFired = false;

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
    return Tooltip(
      message: 'Hold to speak',
      child: GestureDetector(
        onLongPressStart: (_) {
          HapticFeedback.mediumImpact();
          _cancelFired = false;
          widget.onStart();
        },
        onLongPressMoveUpdate: (d) {
          if (_cancelFired) return;
          if (d.offsetFromOrigin.dx < -72) {
            _cancelFired = true;
            HapticFeedback.selectionClick();
            widget.onCancel();
          }
        },
        onLongPressEnd: (_) => widget.onStop(),
        onLongPressCancel: widget.onStop,
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
              color: widget.listening
                  ? const Color(0xFFE53935)
                  : const Color(0xFFE5E7EB),
              boxShadow: widget.listening
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
              color: widget.listening ? Colors.white : Colors.black54,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}
