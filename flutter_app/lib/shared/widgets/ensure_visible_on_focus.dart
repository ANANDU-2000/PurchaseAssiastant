import 'package:flutter/material.dart';

/// Scrolls the wrapped widget into view after [focusNode] gains focus (keyboard safe).
class EnsureVisibleOnFocus extends StatefulWidget {
  const EnsureVisibleOnFocus({
    super.key,
    required this.focusNode,
    required this.child,
    this.delay = const Duration(milliseconds: 85),
    this.alignment = 0.28,
  });

  final FocusNode focusNode;
  final Widget child;
  final Duration delay;
  final double alignment;

  @override
  State<EnsureVisibleOnFocus> createState() => _EnsureVisibleOnFocusState();
}

class _EnsureVisibleOnFocusState extends State<EnsureVisibleOnFocus> {
  final GlobalKey _anchorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant EnsureVisibleOnFocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }
  }

  void _onFocusChange() {
    if (!widget.focusNode.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.focusNode.hasFocus) return;
      Future<void>.delayed(widget.delay, () {
        if (!mounted || !widget.focusNode.hasFocus) return;
        final ctx = _anchorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        final ro = ctx.findRenderObject();
        if (ro == null || !ro.attached) return;
        Scrollable.ensureVisible(
          ctx,
          alignment: widget.alignment,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      });
    });
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _anchorKey,
      child: widget.child,
    );
  }
}
