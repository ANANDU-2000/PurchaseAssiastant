import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/widgets/inline_search_field.dart';

/// Party step only: suggestions render below the field (not an overlay).
/// Filters locally from [controller.text] on every rebuild; [_revealDebounce]
/// coalesces [Scrollable.ensureVisible] so parent scroll stays smooth while typing.
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
    this.maxPanelAbs = 220,
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

  /// Tighter paddings for compact fields.
  final bool dense;

  /// Optional leading icon inside the outlined field.
  final Widget? prefixIcon;

  /// Hard cap on suggestion panel scroll height before keyboard shrinking.
  final double maxPanelAbs;

  @override
  State<PartyInlineSuggestField> createState() =>
      _PartyInlineSuggestFieldState();
}

class _PartyInlineSuggestFieldState extends State<PartyInlineSuggestField> {
  static const _revealDebounce = Duration(milliseconds: 400);

  bool _pickInProgress = false;

  /// After a tap pick, hide panel until text changes or refocus (# subtitle matches).
  bool _suppressPanelAfterPick = false;
  String? _lastPickedLabel;

  /// Coalesces scroll-into-view work while the user is typing.
  Timer? _revealDebounceTimer;

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
    _revealDebounceTimer?.cancel();
    widget.controller.removeListener(_listenCtrl);
    widget.focusNode.removeListener(_listenFocus);
    super.dispose();
  }

  void _listenCtrl() {
    final t = widget.controller.text;
    if (_lastPickedLabel != null && t.trim() != _lastPickedLabel!.trim()) {
      _lastPickedLabel = null;
      if (_suppressPanelAfterPick) {
        _suppressPanelAfterPick = false;
      }
    }
    if (!mounted) return;
    setState(() {});

    _revealDebounceTimer?.cancel();
    _revealDebounceTimer = Timer(_revealDebounce, () {
      if (!mounted) return;
      _maybeRevealAfterFilter();
    });
  }

  void _maybeRevealAfterFilter() {
    if (!widget.focusNode.hasFocus) return;
    final rows = _listRowsForUi();
    final add = widget.showAddRow &&
        widget.focusNode.hasFocus &&
        widget.onAddRow != null;
    if (rows.isNotEmpty || add) _scheduleRevealInScrollView();
  }

  void _listenFocus() {
    final nowFocused = widget.focusNode.hasFocus;
    if (nowFocused) {
      _suppressPanelAfterPick = false;
      _revealDebounceTimer?.cancel();
    } else {
      _tryBlurExactPick();
    }
    if (!mounted) return;
    setState(() {});
    if (nowFocused) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRevealAfterFilter());
    }
  }

  double _effectiveMaxPanelHeight(BuildContext context) {
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final h = MediaQuery.sizeOf(context).height;
    final usableAboveKb = math.max(h - kb, h * 0.45);
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

  List<InlineSearchItem> _filteredFromQuery(String qRaw) {
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

  /// Rows from live controller text — matches appear as soon as typing updates the field.
  List<InlineSearchItem> _listRowsForUi() =>
      _filteredFromQuery(widget.controller.text.trim().toLowerCase());

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
    _revealDebounceTimer?.cancel();
    _suppressPanelAfterPick = true;
    _lastPickedLabel = it.label.trim();
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

  Widget _buildSuggestionTile(ColorScheme cs, InlineSearchItem it) {
    return Material(
      color: cs.surface,
      child: ListTile(
        dense: widget.dense,
        title: Text(
          it.label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        subtitle: (it.subtitle != null && it.subtitle!.trim().isNotEmpty)
            ? Text(
                it.subtitle!.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              )
            : null,
        onTap: () => _pick(it, keepFocus: false),
      ),
    );
  }

  Widget _buildAddRowTile(ColorScheme cs) {
    return Material(
      color: cs.surface,
      child: ListTile(
        dense: true,
        title: Text(
          widget.addRowLabel ?? '',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: cs.primary,
          ),
        ),
        onTap: widget.onAddRow,
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final data = _listRowsForUi();
      if (data.length == 1) {
        _pick(data.first);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _onFieldSubmitted(String _) {
    final data = _listRowsForUi();
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

    final hasPanelSource = !_suppressPanelAfterPick &&
        widget.focusNode.hasFocus &&
        (rows.isNotEmpty || showAddFocused);

    final maxPanelCalc = _effectiveMaxPanelHeight(context);
    final panelScrollH =
        math.min(widget.maxPanelAbs.toDouble(), maxPanelCalc);

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

    final cardShadow = [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.08),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ];

    return KeyedSubtree(
      key: _revealKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field,
          if (hasPanelSource) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: cardShadow,
                border: Border.all(color: borderColor.withValues(alpha: 0.45)),
              ),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: panelScrollH,
                child: ListView(
                  padding: EdgeInsets.zero,
                  physics: const ClampingScrollPhysics(),
                  primary: false,
                  children: [
                    for (final it in rows) _buildSuggestionTile(cs, it),
                    if (rows.isNotEmpty &&
                        showAddFocused &&
                        widget.onAddRow != null)
                      Divider(height: 1, thickness: 1, color: borderColor),
                    if (showAddFocused && widget.onAddRow != null)
                      _buildAddRowTile(cs),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
