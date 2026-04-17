import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../assistant_chat_theme.dart';

/// Subtle dot pattern over the chat scaffold background.
class ChatBackgroundPattern extends StatelessWidget {
  const ChatBackgroundPattern({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AssistantChatTheme.background),
        CustomPaint(painter: _DotsPainter(), size: Size.infinite),
        child,
      ],
    );
  }
}

class _DotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF075E54).withValues(alpha: 0.035)
      ..style = PaintingStyle.fill;
    const step = 28.0;
    for (double x = 0; x < size.width + step; x += step) {
      for (double y = 0; y < size.height + step; y += step) {
        final ox = (y ~/ step).isEven ? 0.0 : step * 0.5;
        canvas.drawCircle(
          Offset(x + ox, y + math.sin(x * 0.02) * 2),
          1.2,
          p,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
