import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/widgets/inline_search_field.dart';

/// Party step only: suggestions render **below** the field (not a floating overlay),
/// capped in height (`maxPanelAbs`, default 250) and further reduced when space is tight
/// above the IME so lists stay scrollable inline instead of sitting under the keyboard.
class PartyInlineSuggestField extends StatefulWidget {
  const PartyInlineSuggestField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.items,
    required this.hintText,
    required this.minQueryLength,
    required this.maxMatches,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.onSelected,
    this.showAddRow = false,
    this.addRowLabel,
    this.onAddRow,
    this.dense = false,
    this.prefixIcon,
    this.maxPanelAbs = 250,
  })  : assert(minQueryLength >= 0),
        assert(
          !showAddRow || (addRowLabel != null && onAddRow != null),
          'showAddRow requires addRowLabel and onAddRow',
        );

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<InlineSearchItem> items;
  final String hintText;
  final int minQueryLength;
  final int maxMatches;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;

  /// Fired when a normal (non–add-row) suggestion is tapped or committed.
  final ValueChanged<InlineSearchItem>? onSelected;

  final bool showAddRow;
  final String? addRowLabel;
  final VoidCallback? onAddRow;

  /// Tighter paddings when two columns sit side by side.
  final bool dense;

  /// Optional leading icon inside the outlined field (parity with Material “party” UX).
  final Widget? prefixIcon;

  /// Hard cap on suggestion panel height before keyboard-aware shrinking.
  final double maxPanelAbs;

  @override
  State<PartyInlineSuggestField> createState() =>
      _PartyInlineSuggestFieldState();
}

class _PartyInlineSuggestFieldState extends State<PartyInlineSuggestField> {
  bool _pickInProgress = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_listenCtrl);
    widget.focusNode.addListener(_listenFocus);
  }

  @override
  void didUpdateWidget(covariant PartyInlineSuggestField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_listenCtrl);
      widget.controller.addListener(_listenCtrl);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_listenFocus);
      widget.focusNode.addListener(_listenFocus);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_listenCtrl);
    widget.focusNode.removeListener(_listenFocus);
    super.dispose();
  }

  void _listenCtrl() {
    setState(() {});
    if (widget.focusNode.hasFocus) {
      final rows = _listRowsForUi();
      final add = widget.showAddRow &&
          widget.focusNode.hasFocus &&
          widget.onAddRow != null;
      if (rows.isNotEmpty || add) _scheduleRevealInScrollView();
    }
  }

  void _listenFocus() {
    final nowFocused = widget.focusNode.hasFocus;
    if (!nowFocused) _tryBlurExactPick();
    setState(() {});
    if (nowFocused) _scheduleRevealInScrollView();
  }

  double _effectiveMaxPanelHeight(BuildContext context) {
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final h = MediaQuery.sizeOf(context).height;
    final usableAboveKb = math.max(h - kb, h * 0.45);
    // Keep list short when vertical space shrinks so it stays scrollable inline, not IME-covered.
    return math.min(
      widget.maxPanelAbs,
      math.max(
        120.0,
        usableAboveKb * 0.42,
      ),
    );
  }

  final GlobalKey _revealKey = GlobalKey(debugLabel: 'partyInlineSuggest');

  void _scheduleRevealInScrollView() {
    void run() {
      if (!mounted || !widget.focusNode.hasFocus) return;
      final ctx = _revealKey.currentContext;
      final ro = ctx?.findRenderObject();
      if (ctx == null || ro == null || !ro.attached) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.06,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => run());
    Future<void>.delayed(const Duration(milliseconds: 140), run);
    Future<void>.delayed(const Duration(milliseconds: 320), run);
  }

  List<InlineSearchItem> _filteredData() {
    final qRaw = widget.controller.text.trim().toLowerCase();
    final min = widget.minQueryLength.clamp(0, 64);
    if (min == 0 && qRaw.isEmpty) {
      return widget.items.take(widget.maxMatches).toList();
    }
    if (qRaw.length < min) return [];
    final out = <InlineSearchItem>[];
    for (final it in widget.items) {
      if (out.length >= widget.maxMatches) break;
      final lab = it.label.toLowerCase();
      final sub = (it.subtitle ?? '').toLowerCase();
      if (lab.contains(qRaw) || sub.contains(qRaw)) out.add(it);
    }
    return out;
  }

  List<InlineSearchItem> _listRowsForUi() => _filteredData();

  EdgeInsets _scrollPad(BuildContext context) {
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final panelReserve = widget.maxPanelAbs.clamp(0.0, 260.0);
    const accessoryFudge = 56.0;
    return EdgeInsets.only(bottom: kb + panelReserve + accessoryFudge);
  }

  void _tryBlurExactPick() {
    if (_pickInProgress) return;
    final q = widget.controller.text.trim().toLowerCase();
    if (q.isEmpty) return;
    final exact = <InlineSearchItem>[];
    for (final it in widget.items) {
      if (it.label.toLowerCase() == q) {
        exact.add(it);
        if (exact.length > 1) return;
      }
    }
    if (exact.length == 1) {
      _pick(exact.first, keepFocus: false);
    }
  }

  void _pick(InlineSearchItem it, {bool keepFocus = true}) {
    _pickInProgress = true;
    widget.controller.text = it.label;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: widget.controller.text.length),
    );
    if (!mounted) {
      _pickInProgress = false;
      return;
    }
    setState(() {});
    try {
      widget.onSelected?.call(it);
    } finally {
      _pickInProgress = false;
    }
    if (!keepFocus) {
      widget.focusNode.unfocus();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final data = _filteredData();
      if (data.length == 1) {
        _pick(data.first);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _onFieldSubmitted(String _) {
    final data = _filteredData();
    if (data.length == 1) {
      _pick(data.first);
      return;
    }
    widget.onSubmitted?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = _listRowsForUi();
    final showAddFocused = widget.showAddRow &&
        widget.focusNode.hasFocus &&
        widget.onAddRow != null;
    final hasPanel =
        widget.focusNode.hasFocus && (rows.isNotEmpty || showAddFocused);
    final maxPanelH = _effectiveMaxPanelHeight(context);

    final borderColor = Colors.grey.shade300;
    final focused = widget.focusNode.hasFocus;

    final vPad = widget.dense ? 12.0 : 14.0;
    final hPad = widget.dense ? 8.0 : 10.0;

    Widget? leading;
    if (widget.prefixIcon != null) {
      leading = Padding(
        padding: EdgeInsets.only(right: widget.dense ? 4 : 6),
        child: IconTheme.merge(
          data: IconThemeData(
            size: widget.dense ? 18 : 22,
            color: cs.primary.withValues(alpha: 0.75),
          ),
          child: widget.prefixIcon!,
        ),
      );
    }

    final fieldPad = leading == null
        ? EdgeInsets.symmetric(horizontal: hPad, vertical: vPad)
        : EdgeInsets.only(right: hPad, top: vPad, bottom: vPad);

    Widget field = Focus(
      onKeyEvent: _onKey,
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        textInputAction: widget.textInputAction,
        onSubmitted: _onFieldSubmitted,
        scrollPadding: _scrollPad(context),
        decoration: InputDecoration(
          hintText: widget.hintText,
          isDense: true,
          hintStyle: TextStyle(
            fontSize: widget.dense ? 13 : 14,
            color: Colors.grey.shade600,
          ),
          border: InputBorder.none,
          isCollapsed: false,
          contentPadding: fieldPad,
        ),
      ),
    );

    field = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: focused ? cs.primary : borderColor,
          width: focused ? 2 : 1,
        ),
      ),
      child: leading == null
          ? field
          : Padding(
              padding: EdgeInsets.only(left: hPad),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  leading,
                  Expanded(child: field),
                ],
              ),
            ),
    );

    return KeyedSubtree(
      key: _revealKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field,
          if (hasPanel) ...[
            const SizedBox(height: 4),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxPanelH),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: ListView(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.zero,
                    children: [
                      for (final it in rows)
                        Material(
                          color: Colors.grey.shade50,
                          child: InkWell(
                            onTap: () => WidgetsBinding.instance
                                .addPostFrameCallback((_) {
                              if (!mounted) return;
                              _pick(it);
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    it.label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (it.subtitle != null &&
                                      it.subtitle!.trim().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        it.subtitle!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (widget.showAddRow &&
                          widget.onAddRow != null &&
                          rows.isNotEmpty)
                        Divider(height: 1, thickness: 1, color: borderColor),
                      if (showAddFocused && widget.onAddRow != null)
                        Material(
                          color: Colors.grey.shade50,
                          child: InkWell(
                            onTap: () => WidgetsBinding.instance
                                .addPostFrameCallback((_) {
                              if (!mounted) return;
                              widget.onAddRow!.call();
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 11,
                              ),
                              child: Text(
                                widget.addRowLabel ?? '',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
