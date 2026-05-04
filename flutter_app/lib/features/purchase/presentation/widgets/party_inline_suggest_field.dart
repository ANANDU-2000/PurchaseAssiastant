import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/hexa_colors.dart';
import '../../../../shared/widgets/inline_search_field.dart';

/// True if [qLower] is empty or matches [label] by **whole-label prefix** or
/// **token prefix** (tokens split on non-alphanumeric).
///
/// Avoids substring noise such as `sura` ⊂ `insurance`.
bool partySuggestLabelMatches(String label, String qLower) {
  if (qLower.isEmpty) return true;
  final lab = label.toLowerCase().trim();
  if (lab.startsWith(qLower)) return true;
  for (final token in lab.split(RegExp(r'[^a-z0-9]+'))) {
    if (token.isNotEmpty && token.startsWith(qLower)) return true;
  }
  return false;
}

int _partySuggestMatchRank(String label, String qLower) {
  if (qLower.isEmpty) return 0;
  final lab = label.toLowerCase().trim();
  if (lab.startsWith(qLower)) return 0;
  return 1;
}

/// Party step: suggestions **inline** below the field (no overlay).
/// Filter is debounced while typing; commits use the live query via [live: true].
///
/// The suggestion list is **not** wrapped in its own [ScrollView]: it grows with
/// the parent scroll (e.g. purchase wizard) so taps are not eaten by nested
/// scroll gesture arenas.
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
    this.maxPanelAbs = 260,
    this.fieldBorderRadius = 8,
    this.idleOutlineColor,
    this.focusedOutlineColor,
    this.fillColor,
    this.minFieldHeight = 0,
    this.lockedSelectionLabel,
    this.onLockedSelectionClear,
    this.focusAfterSelection,
    this.debugLabel,
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

  /// Rounded rectangle around the input (wizard party step uses 12).
  final double fieldBorderRadius;

  /// Outline when unfocused; defaults to neutral grey per theme.
  final Color? idleOutlineColor;

  /// Outline when focused; defaults to [ColorScheme.primary].
  final Color? focusedOutlineColor;

  final Color? fillColor;

  /// When > 0, field row is given at least this height (wizard uses 56).
  final double minFieldHeight;

  /// Non-empty shows a compact “picked” strip until the user taps to search again.
  final String? lockedSelectionLabel;

  final VoidCallback? onLockedSelectionClear;

  /// After committing a suggestion ([keepFocus]==false moves focus here instead of blur-only).
  final FocusNode? focusAfterSelection;

  /// Optional identifier for debug logging.
  final String? debugLabel;

  @override
  State<PartyInlineSuggestField> createState() =>
      _PartyInlineSuggestFieldState();
}

class _PartyInlineSuggestFieldState extends State<PartyInlineSuggestField> {
  static const _filterDebounce = Duration(milliseconds: 400);
  static const _revealDebounce = Duration(milliseconds: 420);

  bool _pickInProgress = false;
  bool _suppressPanelAfterPick = false;
  String? _lastPickedLabel;

  /// Blocks double-commit when both pointer-down and tap-up deliver for one gesture.
  String? _lastCommitFingerprint;
  int _lastCommitMs = 0;

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
    final hits = <InlineSearchItem>[];
    for (final it in widget.items) {
      if (partySuggestLabelMatches(it.label, qRaw)) hits.add(it);
    }
    hits.sort((a, b) {
      final ra = _partySuggestMatchRank(a.label, qRaw);
      final rb = _partySuggestMatchRank(b.label, qRaw);
      final c = ra.compareTo(rb);
      if (c != 0) return c;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return hits.take(widget.maxMatches).toList();
  }

  /// [live]: use typed text immediately (pick / enter / blur).
  List<InlineSearchItem> _listRowsForUi({bool live = false}) {
    final q = live ? widget.controller.text.trim().toLowerCase() : _filterQuery;
    return _filteredFromQuery(q);
  }

  EdgeInsets _scrollPad(BuildContext context) {
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final safe = MediaQuery.paddingOf(context).bottom;
    return EdgeInsets.only(bottom: kb + 240 + safe);
  }

  void _tryBlurExactPick() {
    if (_pickInProgress) return;
    // Tap selection sets this before blur; avoid a second _pick from blur exact-match.
    if (_suppressPanelAfterPick) return;
    _flushFilterToLive();
    final q = widget.controller.text.trim().toLowerCase();
    if (q.isEmpty) return;

    // One visible filtered row — commit on blur when the list tap was eaten.
    // Require 2+ chars so single-letter queries do not auto-pick the wrong supplier.
    final narrowed = _listRowsForUi(live: true);
    if (q.length >= 2 && narrowed.length == 1) {
      _pick(narrowed.first, keepFocus: false);
      return;
    }

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

  /// Pointer-down plus tap-up can both fire `_pick`; blocks the second commit.
  bool _consumeIfDuplicatePick(InlineSearchItem it) {
    final fp = '${it.id}\u241e${it.label}';
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastCommitFingerprint == fp && now - _lastCommitMs < 400) {
      return true;
    }
    _lastCommitFingerprint = fp;
    _lastCommitMs = now;
    return false;
  }

  void _pick(InlineSearchItem it, {bool keepFocus = true}) {
    if (_consumeIfDuplicatePick(it)) return;
    _filterDebounceTimer?.cancel();
    _revealDebounceTimer?.cancel();
    _suppressPanelAfterPick = true;
    _lastPickedLabel = it.label.trim();
    _filterQuery = it.label.trim().toLowerCase();

    // Sync controller update first — use .value to avoid double-trigger of text listeners
    widget.controller.value = TextEditingValue(
      text: it.label,
      selection: TextSelection.collapsed(offset: it.label.length),
    );

    // Call parent SYNCHRONOUSLY before any unfocus or setState.
    // This commits the Riverpod draft while the widget tree is stable.
    if (widget.onSelected != null) {
      _pickInProgress = true;
      try {
        widget.onSelected!.call(it);
      } finally {
        _pickInProgress = false;
      }
    }

    // Rebuild to hide the panel
    if (mounted) setState(() {});

    if (kDebugMode) {
      final tag = widget.debugLabel != null ? ' ${widget.debugLabel}' : '';
      debugPrint('[PartySuggest$tag] pick id="${it.id}" label="${it.label}" '
          'focusNext=${widget.focusAfterSelection != null} keepFocus=$keepFocus');
    }

    // Focus hand-off AFTER parent is notified — deferred avoids gesture/blur swallowing taps.
    if (!keepFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final next = widget.focusAfterSelection;
        if (next != null) {
          FocusScope.of(context).requestFocus(next);
        } else {
          widget.focusNode.unfocus();
          FocusManager.instance.primaryFocus?.unfocus();
        }
      });
    }
  }

  Widget _buildSuggestionTile(ColorScheme cs, InlineSearchItem it) {
    return Material(
      color: cs.surface,
      child: InkWell(
        onTap: () => _pick(it, keepFocus: false),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: widget.dense ? 10 : 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                it.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: cs.onSurface,
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
      ),
    );
  }

  Widget _buildAddRowTile(ColorScheme cs) {
    final cb = widget.onAddRow;
    if (cb == null) {
      return const SizedBox.shrink();
    }
    void invoke() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.focusNode.unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
        Future.delayed(const Duration(milliseconds: 80), () => cb());
      });
    }

    return Material(
      color: cs.surface,
      child: InkWell(
        onTap: invoke,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
        _pick(data.first, keepFocus: false);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _onFieldSubmitted(String _) {
    _flushFilterToLive();
    final data = _listRowsForUi(live: true);
    if (data.length == 1) {
      _pick(data.first, keepFocus: false);
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

    final lockLabel = widget.lockedSelectionLabel?.trim();
    final locked = lockLabel != null &&
        lockLabel.isNotEmpty &&
        !widget.focusNode.hasFocus;

    final hasPanelSource = !locked &&
        !_suppressPanelAfterPick &&
        widget.focusNode.hasFocus &&
        (rows.isNotEmpty || showAddFocused);

    final borderColor = widget.idleOutlineColor ?? Colors.grey.shade200;
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
            color: HexaColors.brandPrimary.withValues(alpha: 0.82),
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
            color: Colors.grey.shade500,
          ),
          border: InputBorder.none,
          isCollapsed: false,
          contentPadding: fieldPad,
        ),
      ),
    );

    final outlineClr = focused
        ? (widget.focusedOutlineColor ?? HexaColors.brandPrimary)
        : borderColor;

    Widget innerInput = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      constraints: widget.minFieldHeight > 0
          ? BoxConstraints(minHeight: widget.minFieldHeight)
          : null,
      decoration: BoxDecoration(
        color: widget.fillColor ?? Colors.grey.shade50,
        borderRadius: BorderRadius.circular(widget.fieldBorderRadius),
        border: Border.all(
          color: outlineClr,
          width: focused ? 2 : 1,
        ),
      ),
      alignment: Alignment.centerLeft,
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

    if (locked) {
      final clearCb = widget.onLockedSelectionClear;
      innerInput = AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        constraints: BoxConstraints(minHeight: widget.minFieldHeight > 0 ? widget.minFieldHeight : 52),
        decoration: BoxDecoration(
          color: widget.fillColor ?? Colors.grey.shade50,
          borderRadius: BorderRadius.circular(widget.fieldBorderRadius),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(widget.fieldBorderRadius),
          onTap: () => widget.focusNode.requestFocus(),
          child: Padding(
            padding: EdgeInsets.only(left: hPad, right: 2),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: HexaColors.brandPrimary,
                  size: widget.dense ? 20 : 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lockLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: widget.dense ? 14 : 15,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Clear',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, color: Colors.grey.shade700, size: 20),
                  onPressed: clearCb,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final fieldWrapped = innerInput;

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
          fieldWrapped,
          if (hasPanelSource) ...[
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: cardShadow,
                border: Border.all(color: borderColor.withValues(alpha: 0.45)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
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
            ),
          ],
        ],
      ),
    );
  }
}
