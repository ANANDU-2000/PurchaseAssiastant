import 'package:flutter/material.dart';

import '../hexa_ds_tokens.dart';
import '../hexa_responsive.dart';

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

/// Responsive short-field pair: side-by-side from [kTabletMin], stacked on phone.
///
/// Use for Item code/HSN, Tax %/Unit, Payment days/Discount %, etc.
/// Keep Name, Narration, and search fields full-width outside this widget.
class AppFormRow extends StatelessWidget {
  const AppFormRow({
    super.key,
    required this.children,
    this.gap = HexaDsSpace.s2,
  });

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length == 1) return children.first;

    final wide = MediaQuery.sizeOf(context).width >= kTabletMin;
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}
