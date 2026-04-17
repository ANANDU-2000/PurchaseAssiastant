import 'package:flutter/material.dart';

import '../assistant_chat_theme.dart';

/// Circular WhatsApp-like send CTA with subtle press-scale feedback.
class SendButton extends StatefulWidget {
  const SendButton({
    super.key,
    required this.onPressed,
    required this.loading,
  });

  final VoidCallback? onPressed;
  final bool loading;

  @override
  State<SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<SendButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _press.forward(),
      onTapCancel: () => _press.reverse(),
      onTapUp: (_) => _press.reverse(),
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, child) {
          final scale = 1.0 - (0.06 * _press.value);
          return Transform.scale(scale: scale, child: child);
        },
        child: FilledButton(
          onPressed: widget.loading ? null : widget.onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AssistantChatTheme.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.all(12),
            minimumSize: const Size(46, 46),
            shape: const CircleBorder(),
            elevation: 0,
          ),
          child: widget.loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.send_rounded, size: 21),
        ),
      ),
    );
  }
}
