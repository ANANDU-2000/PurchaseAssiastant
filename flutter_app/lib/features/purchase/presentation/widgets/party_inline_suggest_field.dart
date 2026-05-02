import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/widgets/inline_search_field.dart';

/// Party step: suggestions **inline** below the field (no overlay).
/// Filter is debounced while typing; commits use the live query via [live: true].
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
    this.maxPanelAbs = 200,
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

  final bool dense;
  final Widget? prefixIcon;

  /// Hard cap on suggestion panel height (default 200).
  final double maxPanelAbs;

  @override
  State<PartyInlineSuggestField> createState() =>
      _PartyInlineSuggestFieldState();
}

class _PartyInlineSuggestFieldState extends State<PartyInlineSuggestField> {
  static const _filterDebounce = Duration(milliseconds: 350);
  static const _revealDebounce = Duration(milliseconds: 400);

  bool _pickInProgress = false;
  bool _suppressPanelAfterPick = false;
  String? _lastPickedLabel;

  /// Debounced query for filtering while typing ([_listRowsForUi]).
  String _filterQuery = '';
  Timer? _filterDebounceTimer;
  Timer? _revealDebounceTimer;

  final GlobalKey _revealKey = GlobalKey(debugLabel: 'partyInlineSuggest');

  @override
  void initState() {
    super.initState();
    _filterQuery = widget.controller.text.trim().toLowerCase();
    widget.controller.addListener(_listenCtrl);
    widget.focusNode.addListener(_listenFocus);
  }

  @override
  void didUpdateWidget(covariant PartyInlineSuggestField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_listenCtrl);
      widget.controller.addListener(_listenCtrl);
      _filterQuery = widget.controller.text.trim().toLowerCase();
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_listenFocus);
      widget.focusNode.addListener(_listenFocus);
    }
  }

  @override
  void dispose() {
    _filterDebounceTimer?.cancel();
    _revealDebounceTimer?.cancel();
    widget.controller.removeListener(_listenCtrl);
    widget.focusNode.removeListener(_listenFocus);
    super.dispose();
  }

  void _flushFilterToLive() {
    _filterDebounceTimer?.cancel();
    final live = widget.controller.text.trim().toLowerCase();
    if (_filterQuery != live) {
      setState(() => _filterQuery = live);
    }
  }

  void _listenCtrl() {
    final t = widget.controller.text;
    if (_lastPickedLabel != null && t.trim() != _lastPickedLabel!.trim()) {
      _lastPickedLabel = null;
      if (_suppressPanelAfterPick) {
        _suppressPanelAfterPick = false;
        if (mounted) setState(() {});
      }
    }
    if (!mounted) return;

    _filterDebounceTimer?.cancel();
    _filterDebounceTimer = Timer(_filterDebounce, () {
      if (!mounted) return;
      setState(() {
        _filterQuery = widget.controller.text.trim().toLowerCase();
      });
      _maybeRevealAfterFilter();
    });

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
      _filterDebounceTimer?.cancel();
      _revealDebounceTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _filterQuery = widget.controller.text.trim().toLowerCase();
      });
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _maybeRevealAfterFilter());
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.focusNode.hasFocus) return;
      _tryBlurExactPick();
      if (!mounted) return;
      setState(() {});
    });
  }

  void _scheduleRevealInScrollView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.focusNode.hasFocus) return;
      final ctx = _revealKey.currentContext;
      final ro = ctx?.findRenderObject();
      if (ctx == null || ro == null || !ro.attached) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
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

  /// [live]: use typed text immediately (pick / enter / blur).
  List<InlineSearchItem> _listRowsForUi({bool live = false}) {
    final q = live ? widget.controller.text.trim().toLowerCase() : _filterQuery;
    return _filteredFromQuery(q);
  }

  EdgeInsets _scrollPad(BuildContext context) {
    final safe = MediaQuery.paddingOf(context).bottom;
    return EdgeInsets.only(bottom: 96 + safe);
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
    _filterDebounceTimer?.cancel();
    _revealDebounceTimer?.cancel();
    _suppressPanelAfterPick = true;
    _lastPickedLabel = it.label.trim();
    _filterQuery = it.label.trim().toLowerCase();
    if (!mounted) {
      _pickInProgress = false;
      return;
    }
    try {
      // Commit visible text before parent handlers (Riverpod/sync can rebuild).
      widget.controller.text = it.label;
      widget.controller.selection = TextSelection.fromPosition(
        TextPosition(offset: widget.controller.text.length),
      );
      widget.onSelected?.call(it);
    } finally {
      _pickInProgress = false;
    }
    if (!mounted) return;
    setState(() {});
    if (!keepFocus) {
      widget.focusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  Widget _buildSuggestionTile(ColorScheme cs, InlineSearchItem it) {
    return Material(
      color: cs.surface,
      child: TextButton(
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: widget.dense ? 10 : 12,
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: cs.onSurface,
        ),
        onPressed: () => _pick(it, keepFocus: false),
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
            if (it.subtitle != null && it.subtitle!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  it.subtitle!.trim(),
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
    );
  }

  Widget _buildAddRowTile(ColorScheme cs) {
    return Material(
      color: cs.surface,
      child: TextButton(
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: widget.onAddRow,
        child: Align(
          alignment: Alignment.centerLeft,
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
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _flushFilterToLive();
      final data = _listRowsForUi(live: true);
      if (data.length == 1) {
        _pick(data.first);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _onFieldSubmitted(String _) {
    _flushFilterToLive();
    final data = _listRowsForUi(live: true);
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
              // Single scroll ancestor: expanded Column (no nested ListView).
              // Parent wizard `SingleChildScrollView` handles overflow; taps reach tiles reliably.
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
          ],
        ],
      ),
    );
  }
}
