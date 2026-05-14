import 'package:flutter/material.dart';

/// Pushes [child] above the IME using [MediaQuery.viewInsetsOf] with a short
/// animation. Pair with [Scaffold.resizeToAvoidBottomInset] **or** use inside a
/// parent that already pads for the keyboard — avoid double-counting insets
/// (see [KeyboardSafeFormViewport.useViewInsetBottom]).
class KeyboardLiftedFooter extends StatelessWidget {
  const KeyboardLiftedFooter({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 200),
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: duration,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: kb),
      child: SafeArea(top: false, maintainBottomViewPadding: true, child: child),
    );
  }
}
