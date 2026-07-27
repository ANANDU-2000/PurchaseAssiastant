import 'package:flutter/material.dart';

/// Single-scroll form body under [Scaffold] with [resizeToAvoidBottomInset].
///
/// **Bottom padding:** with [useViewInsetBottom] false (default), uses
/// [bottomExtraInset] + [MediaQuery.paddingOf] bottom only — the scaffold already
/// shrinks the body for the IME, so adding [viewInsets] here would double-count.
/// Set [useViewInsetBottom] true for parents that keep [resizeToAvoidBottomInset]: false
/// (e.g. [AuthPageShell]).
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
    this.bottomExtraInset = 60,
    /// When > 0, wraps [fields] so nested [Expanded]/[Spacer] get bounded height.
    this.minFieldsHeight = 0,
    this.dismissKeyboardOnTap = false,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.onDrag,
    this.primaryScroll = false,
    /// When false (default): bottom pad = safe area inset + [bottomExtraInset].
    /// When true: also add view insets (for parents that keep [resizeToAvoidBottomInset]: false).
    this.useViewInsetBottom = false,
  });

  final Widget? prepend;
  final Widget fields;
  final Widget footer;
  final Widget? append;

  final ScrollController? scrollController;

  final double horizontalPadding;
  final double topPadding;
  final double bottomExtraInset;
  final double minFieldsHeight;

  final bool dismissKeyboardOnTap;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;
  final bool primaryScroll;
  final bool useViewInsetBottom;

  @override
  Widget build(BuildContext context) {
    final viewPaddingBottom = MediaQuery.paddingOf(context).bottom;
    final insetBottom = MediaQuery.viewInsetsOf(context).bottom;
    final bottomPad = bottomExtraInset +
        viewPaddingBottom +
        (useViewInsetBottom ? insetBottom : 0);

    Widget viewport = LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        final hasBoundedH = maxH.isFinite && maxH > 0;
        final minColHeight = hasBoundedH ? maxH : 0.0;

        Widget inner = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (prepend != null) prepend!,
            if (minFieldsHeight > 0)
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: minFieldsHeight),
                child: fields,
              )
            else
              fields,
            if (append != null) ...[
              const SizedBox(height: 12),
              append!,
            ],
            const SizedBox(height: 16),
            SafeArea(
              top: false,
              maintainBottomViewPadding: true,
              child: footer,
            ),
          ],
        );

        if (minColHeight > 0) {
          inner = ConstrainedBox(
            constraints: BoxConstraints(minHeight: minColHeight),
            child: inner,
          );
        }

        return SingleChildScrollView(
          controller: scrollController,
          primary: primaryScroll,
          physics: const ClampingScrollPhysics(),
          keyboardDismissBehavior: keyboardDismissBehavior,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding,
            horizontalPadding,
            bottomPad,
          ),
          child: inner,
        );
      },
    );

    if (dismissKeyboardOnTap) {
      viewport = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: viewport,
      );
    }

    return viewport;
  }
}
