import 'package:flutter/material.dart';

/// Keyboard-aware scroll viewport: scrollable fields + footer aligned to bottom
/// when short, with bottom inset for IME. Prefer over pinned [Scaffold.bottomNavigationBar].
///
/// Footer is scrolled with content so it stays above the keyboard when fields grow.
class KeyboardSafeFormViewport extends StatelessWidget {
  const KeyboardSafeFormViewport({
    super.key,
    this.prepend,
    required this.fields,
    required this.footer,
    this.append,
    this.scrollController,
    this.horizontalPadding = 16,
    this.topPadding = 12,
    this.bottomExtraInset = 20,
    /// When > 0, wraps [fields] in [ConstrainedBox] so descendants like
    /// `Expanded` / `Spacer` get a bounded height (e.g. nested wizard steps).
    this.minFieldsHeight = 0,
    this.dismissKeyboardOnTap = false,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.onDrag,
    this.primaryScroll = false,
  });

  /// Full-width widgets above padded fields (e.g. banners).
  final Widget? prepend;

  /// Main form body (typically a [Column]); given max width via padding.
  final Widget fields;

  /// Pinned visually to bottom when space allows; scrolls above keyboard when tall.
  final Widget footer;

  /// Placed inside the padded region after [fields].
  final Widget? append;

  final ScrollController? scrollController;

  final double horizontalPadding;

  final double topPadding;

  final double bottomExtraInset;

  final double minFieldsHeight;

  final bool dismissKeyboardOnTap;

  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  final bool primaryScroll;

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.viewInsetsOf(context).bottom;

    Widget body = CustomScrollView(
      controller: scrollController,
      primary: primaryScroll,
      keyboardDismissBehavior: keyboardDismissBehavior,
      physics: const ClampingScrollPhysics(),
      slivers: [
        if (prepend != null) SliverToBoxAdapter(child: prepend!),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding,
            horizontalPadding,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: minFieldsHeight > 0
                ? ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minFieldsHeight),
                    child: fields,
                  )
                : fields,
          ),
        ),
        if (append != null)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12,
              horizontalPadding,
              0,
            ),
            sliver: SliverToBoxAdapter(child: append!),
          ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12,
              horizontalPadding,
              kb + bottomExtraInset,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SafeArea(
                  top: false,
                  maintainBottomViewPadding: true,
                  child: footer,
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (dismissKeyboardOnTap) {
      body = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: body,
      );
    }

    return body;
  }
}
