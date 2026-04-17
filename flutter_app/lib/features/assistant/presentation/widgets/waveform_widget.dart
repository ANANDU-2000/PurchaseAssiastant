import 'dart:math';

import 'package:flutter/material.dart';

import '../assistant_chat_theme.dart';

/// Animated bars for live recording state.
class WaveformWidget extends StatefulWidget {
  const WaveformWidget({
    super.key,
    this.barCount = 22,
    this.color = AssistantChatTheme.accent,
    this.minHeight = 4,
    this.maxHeight = 18,
  });

  final int barCount;
  final Color color;
  final double minHeight;
  final double maxHeight;

  @override
  State<WaveformWidget> createState() => _WaveformWidgetState();
}

class _WaveformWidgetState extends State<WaveformWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<double> _bars;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _bars = List<double>.filled(widget.barCount, 0.5);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(_tick);
    _controller.repeat();
  }

  void _tick() {
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < _bars.length; i++) {
        final base = 0.25 + ((i % 5) * 0.12);
        final wobble = (_controller.value * 0.45) + (_rng.nextDouble() * 0.2);
        _bars[i] = (base + wobble).clamp(0.15, 1.0);
      }
    });
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_tick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _bars
          .map(
            (h) => AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: AssistantChatTheme.motion,
              width: 3,
              height: widget.minHeight + ((widget.maxHeight - widget.minHeight) * h),
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}
