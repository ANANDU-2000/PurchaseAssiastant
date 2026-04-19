import 'package:flutter/material.dart';

import '../hexa_ds_tokens.dart';

/// Vertical form stack with consistent **8px grid** spacing between children.
class AppFormLayout extends StatelessWidget {
  const AppFormLayout({
    super.key,
    required this.children,
    /// Gap as multiples of 8px (default `2` → 16px).
    this.gapUnits = 2,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    this.scrollable = true,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> children;
  final int gapUnits;
  final CrossAxisAlignment crossAxisAlignment;
  final bool scrollable;
  final EdgeInsetsGeometry padding;

  double get _gap => HexaDsSpace.grid(gapUnits);

  @override
  Widget build(BuildContext context) {
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) spaced.add(SizedBox(height: _gap));
      spaced.add(children[i]);
    }

    final column = Column(
      crossAxisAlignment: crossAxisAlignment,
      children: spaced,
    );

    if (!scrollable) {
      return Padding(padding: padding, child: column);
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: padding,
      child: column,
    );
  }
}
