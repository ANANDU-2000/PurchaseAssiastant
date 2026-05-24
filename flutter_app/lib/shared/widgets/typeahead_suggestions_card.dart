import 'package:flutter/material.dart';

/// Scrollable suggestion panel under a search field (Tally / POS style).
///
/// Wraps a [ListView] or similar in a [Card] with a max height so the parent
/// [ListView] does not grow without bound. Optional [footer] renders below the
/// scroll area (e.g. “Create new…” row).
class TypeaheadSuggestionsCard extends StatelessWidget {
  const TypeaheadSuggestionsCard({
    super.key,
    this.maxHeight = 240.0,
    this.margin = EdgeInsets.zero,
    required this.child,
    this.footer,
  });

  final double maxHeight;
  final EdgeInsetsGeometry margin;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight, minHeight: 0),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: child,
            ),
          ),
          if (footer != null) footer!,
        ],
      ),
    );
  }
}
