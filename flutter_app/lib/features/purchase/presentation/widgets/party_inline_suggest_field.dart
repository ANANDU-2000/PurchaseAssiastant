import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/widgets/form_field_scroll.dart';
import '../../../../shared/widgets/inline_search_field.dart';
import '../../../../shared/widgets/smart_search_field.dart';

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

int _rankLabelTokenMatch(String labLower, String qLower) {
  if (qLower.isEmpty) return 0;
  if (labLower.startsWith(qLower)) return 0;
  final toks = labLower
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (toks.isNotEmpty && toks.first.startsWith(qLower)) return 1;
  for (var i = 1; i < toks.length; i++) {
    if (toks[i].startsWith(qLower)) return 2;
  }
  return 3;
}

String _partyMatchBlobLower(InlineSearchItem it) {
  final s = it.searchText?.trim();
  if (s != null && s.isNotEmpty) return s.toLowerCase();
  return it.label.toLowerCase().trim();
}

bool _partySuggestHasHaystack(InlineSearchItem it) {
  final s = it.searchText?.trim();
  return s != null && s.isNotEmpty;
}

/// Party rows (no [InlineSearchItem.searchText]): prefix + token-prefix only, plus
/// **multi-word AND** (each word must match via [partySuggestLabelMatches]).
///
/// Catalog rows (haystack set): also match **substring** on the blob and require
/// **every** space-separated word to appear (prefix/token or substring), so any
/// letter or word in name/code/HSN can surface a selectable row.
bool partySuggestItemMatchesQuery(InlineSearchItem it, String qLower) {
  if (qLower.isEmpty) return true;
  final blob = _partyMatchBlobLower(it);
  final haystack = _partySuggestHasHaystack(it);

  if (partySuggestLabelMatches(blob, qLower)) return true;

  final words = qLower
      .split(RegExp(r'\s+'))
      .map((w) => w.trim())
      .where((w) => w.isNotEmpty)
      .toList();

  if (haystack) {
    if (blob.contains(qLower)) return true;
    if (words.length > 1) {
      return words.every(
        (w) => partySuggestLabelMatches(blob, w) || blob.contains(w),
      );
    }
    if (words.length == 1) {
      return blob.contains(words.first);
    }
    return false;
  }

  if (words.length > 1) {
    return words.every((w) => partySuggestLabelMatches(blob, w));
  }

  return false;
}

/// Best rank for sorting: label match quality first, then extended [searchText] blob.
int _partySuggestItemMatchRank(InlineSearchItem it, String qLower) {
  if (qLower.isEmpty) return 0;
  final lab = it.label.toLowerCase().trim();
  final blob = _partyMatchBlobLower(it);
  final haystack = _partySuggestHasHaystack(it);
  final rLab = _rankLabelTokenMatch(lab, qLower);
  if (rLab < 3) return rLab;
  if (blob != lab) {
    if (partySuggestLabelMatches(blob, qLower)) {
      final rb = _rankLabelTokenMatch(blob, qLower);
      return 3 + math.min(2, rb);
    }
    if (haystack && blob.contains(qLower)) return 6;
  } else if (haystack &&
      blob.contains(qLower) &&
      !partySuggestLabelMatches(blob, qLower)) {
    return 6;
  }
  return 7;
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
    this.hintStyle,
    this.minFieldHeight = 0,
    this.lockedSelectionLabel,
    this.onLockedSelectionClear,
    this.focusAfterSelection,
    this.debugLabel,
    /// When true, suggestions render in an [Overlay] below the field (full-page
    /// catalog pick) so the IME does not cover the list. Party step stays inline.
    this.suggestionsAsOverlay = false,
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

  /// Optional hint typography (e.g. higher contrast on purchase item sheet).
  final TextStyle? hintStyle;

  /// When > 0, field row is given at least this height (wizard uses 56).
  final double minFieldHeight;

  /// Non-empty shows a compact “picked” strip until the user taps to search again.
  final String? lockedSelectionLabel;

  final VoidCallback? onLockedSelectionClear;

  /// After committing a suggestion ([keepFocus]==false moves focus here instead of blur-only).
  final FocusNode? focusAfterSelection;

  /// Optional identifier for debug logging.
  final String? debugLabel;

  /// See [PartyInlineSuggestField.suggestionsAsOverlay] on the constructor.
  final bool suggestionsAsOverlay;

  @override
  State<PartyInlineSuggestField> createState() =>
      _PartyInlineSuggestFieldState();
}

class _PartyInlineSuggestFieldState extends State<PartyInlineSuggestField> {
  static const _filterDebounce = Duration(milliseconds: 300);
  static const _revealDebounce = Duration(milliseconds: 280);
  static const _maxHitsSheet = 200;

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
  /// After the field loses focus (e.g. finger down on a suggestion), keep the panel
  /// on screen briefly so row taps complete. Otherwise the list could unmount before
  /// the tap lands (supplier / broker / item pick felt "dead" on some devices).
  Timer? _suggestPanelGraceTimer;
  bool _suggestPanelGrace = false;

  /// Overlay mode: after IME dismiss (focus lost), keep the panel until Close or pick.
  bool _overlayStayOpenUntilDismiss = false;

  final GlobalKey _revealKey = GlobalKey(debugLabel: 'partyInlineSuggest');
  final GlobalKey _fieldMeasureKey = GlobalKey(debugLabel: 'partyInlineField');
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _suggestionOverlayEntry;

  /// Groups the text field and overlay panel so [TapRegion.onTapOutside] does not
  /// fire when the user taps a suggestion (overlay is not a descendant of the field).
  final Object _suggestionTapGroup = Object();

  /// Shared with overlay [Scrollbar] + [ListView] so the thumb tracks drags.
  final ScrollController _overlaySuggestScroll = ScrollController();

  /// Inline panel (non-overlay): same ScrollController pairing as overlay.
  final ScrollController _inlineSuggestScroll = ScrollController();

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
    if (oldWidget.suggestionsAsOverlay != widget.suggestionsAsOverlay &&
        !widget.suggestionsAsOverlay) {
      _removeSuggestionOverlay();
    }
  }

  @override
  void dispose() {
    _removeSuggestionOverlay();
    _overlaySuggestScroll.dispose();
    _inlineSuggestScroll.dispose();
    _filterDebounceTimer?.cancel();
    _revealDebounceTimer?.cancel();
    _suggestPanelGraceTimer?.cancel();
    widget.controller.removeListener(_listenCtrl);
    widget.focusNode.removeListener(_listenFocus);
    super.dispose();
  }

  void _cancelSuggestPanelGrace() {
    _suggestPanelGraceTimer?.cancel();
    _suggestPanelGraceTimer = null;
    _suggestPanelGrace = false;
  }

  void _armSuggestPanelGraceIfNeeded() {
    final lock = widget.lockedSelectionLabel?.trim();
    if (lock != null && lock.isNotEmpty) {
      _cancelSuggestPanelGrace();
      return;
    }
    _suggestPanelGraceTimer?.cancel();
    _flushFilterToLive();
    final rows = _listRowsForUi(live: true);
    final canAdd = widget.showAddRow && widget.onAddRow != null;
    if (rows.isEmpty && !canAdd) {
      _suggestPanelGrace = false;
      return;
    }
    _suggestPanelGrace = true;
    _suggestPanelGraceTimer = Timer(const Duration(milliseconds: 420), () {
      _suggestPanelGraceTimer = null;
      _suggestPanelGrace = false;
      if (!mounted) return;
      if (!widget.focusNode.hasFocus &&
          !_pickInProgress &&
          !_suppressPanelAfterPick) {
        _tryBlurExactPick();
      }
      setState(() {});
      _scheduleOverlaySync();
    });
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
      _scheduleOverlaySync();
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
      _cancelSuggestPanelGrace();
      _overlayStayOpenUntilDismiss = false;
      _suppressPanelAfterPick = false;
      _filterDebounceTimer?.cancel();
      _revealDebounceTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _filterQuery = widget.controller.text.trim().toLowerCase();
      });
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _maybeRevealAfterFilter());
      _scheduleOverlaySync();
      return;
    }
    // Full-page overlay: keep suggestions open after keyboard dismiss until user
    // picks, taps Close, or focuses the field again.
    if (widget.suggestionsAsOverlay) {
      _flushFilterToLive();
      final rows = _listRowsForUi(live: true);
      final canAdd =
          widget.showAddRow && widget.onAddRow != null;
      if (rows.isNotEmpty || canAdd) {
        _overlayStayOpenUntilDismiss = true;
      }
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.focusNode.hasFocus) return;
        setState(() {});
        _scheduleOverlaySync();
      });
      return;
    }
    _armSuggestPanelGraceIfNeeded();
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.focusNode.hasFocus) return;
      setState(() {});
      _scheduleOverlaySync();
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

  List<InlineSearchItem> _sortedHitsCapped(String qRaw, int cap) {
    final min = widget.minQueryLength.clamp(0, 64);
    if (min == 0 && qRaw.isEmpty) {
      final list = widget.items.toList()
        ..sort(
          (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
        );
      return list.take(cap).toList();
    }
    if (qRaw.length < min) return [];
    final hits = <InlineSearchItem>[];
    for (final it in widget.items) {
      if (partySuggestItemMatchesQuery(it, qRaw)) {
        hits.add(it);
      }
    }
    hits.sort((a, b) {
      final ra = _partySuggestItemMatchRank(a, qRaw);
      final rb = _partySuggestItemMatchRank(b, qRaw);
      final c = ra.compareTo(rb);
      if (c != 0) return c;
      final sb = b.sortBoost.compareTo(a.sortBoost);
      if (sb != 0) return sb;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return hits.take(cap).toList();
  }

  /// [live]: use typed text immediately (pick / enter / blur).
  List<InlineSearchItem> _listRowsForUi({bool live = false}) {
    final q = live ? widget.controller.text.trim().toLowerCase() : _filterQuery;
    return _sortedHitsCapped(q, widget.maxMatches);
  }

  List<InlineSearchItem> _allHitsForSheet(String qRaw) =>
      _sortedHitsCapped(qRaw, _maxHitsSheet);

  Future<void> _openSeeAllSheet() async {
    _flushFilterToLive();
    final q = widget.controller.text.trim().toLowerCase();
    final all = _allHitsForSheet(q);
    if (all.isEmpty || !mounted) return;
    final title = widget.hintText.trim().isEmpty ? 'Matches' : widget.hintText;
    await showSmartSearchResultsSheet(
      context: context,
      title: title,
      resultCount: all.length,
      items: all,
      onPick: (it) => _pick(it, keepFocus: false),
      buildTile: (c, cs, it, onTap) {
        return Material(
          color: cs.surface,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(minHeight: 48, minWidth: double.infinity),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      it.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
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
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
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
    _cancelSuggestPanelGrace();
    _overlayStayOpenUntilDismiss = false;
    _filterDebounceTimer?.cancel();
    _revealDebounceTimer?.cancel();
    _suppressPanelAfterPick = true;
    _lastPickedLabel = it.label.trim();
    _filterQuery = it.label.trim().toLowerCase();

    // Call parent before updating [controller]: the parent's text listener may run
    // synchronously on controller changes; if [onSelected] commits the new catalog
    // id after the text update, a stale id can still be set and the listener clears
    // selection (label vs previous row name mismatch).
    if (widget.onSelected != null) {
      _pickInProgress = true;
      try {
        widget.onSelected!.call(it);
      } finally {
        _pickInProgress = false;
      }
    }
    HapticFeedback.selectionClick();

    widget.controller.value = TextEditingValue(
      text: it.label,
      selection: TextSelection.collapsed(offset: it.label.length),
    );

    // Rebuild to hide the panel
    if (mounted) setState(() {});
    _scheduleOverlaySync();

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
    void commit() => _pick(it, keepFocus: false);
    return Material(
      type: MaterialType.transparency,
      color: cs.surface,
      child: InkWell(
        onTap: commit,
        hoverColor: cs.primary.withValues(alpha: 0.05),
        splashColor: cs.primary.withValues(alpha: 0.10),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minHeight: 44, minWidth: double.infinity),
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
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        height: 1.2,
                      ),
                    ),
                  ),
              ],
            ),
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
      widget.focusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
      // One post-frame hop (no extra 80ms delay): stacked delays made web taps
      // feel dead and could race rebuilds before [Navigator.push] in the wizard.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        cb();
      });
    }

    return Material(
      type: MaterialType.transparency,
      color: cs.surface,
      child: InkWell(
        onTap: invoke,
        hoverColor: cs.primary.withValues(alpha: 0.06),
        splashColor: cs.primary.withValues(alpha: 0.12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: double.infinity),
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

  void _removeSuggestionOverlay() {
    _suggestionOverlayEntry?.remove();
    _suggestionOverlayEntry = null;
  }

  void _scheduleOverlaySync() {
    if (!widget.suggestionsAsOverlay) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSuggestionOverlay();
    });
  }

  bool _panelVisibleForOverlay() {
    final lockLabel = widget.lockedSelectionLabel?.trim();
    final locked = lockLabel != null &&
        lockLabel.isNotEmpty &&
        !widget.focusNode.hasFocus;
    final rows = _listRowsForUi();
    final suggestInteractive = widget.focusNode.hasFocus ||
        _suggestPanelGrace ||
        (widget.suggestionsAsOverlay && _overlayStayOpenUntilDismiss);
    final showAddFocused =
        widget.showAddRow && suggestInteractive && widget.onAddRow != null;
    return !locked &&
        !_suppressPanelAfterPick &&
        suggestInteractive &&
        (rows.isNotEmpty || showAddFocused);
  }

  void _syncSuggestionOverlay() {
    if (!widget.suggestionsAsOverlay) {
      _removeSuggestionOverlay();
      return;
    }
    if (!_panelVisibleForOverlay()) {
      _removeSuggestionOverlay();
      return;
    }
    if (_suggestionOverlayEntry == null) {
      _suggestionOverlayEntry = OverlayEntry(
        maintainState: true,
        builder: (ctx) => _buildOverlaySuggestions(ctx),
      );
      Overlay.of(context).insert(_suggestionOverlayEntry!);
    } else {
      _suggestionOverlayEntry!.markNeedsBuild();
    }
  }

  Widget _buildOverlaySuggestions(BuildContext overlayCtx) {
    final cs = Theme.of(overlayCtx).colorScheme;
    final rows = _listRowsForUi();
    final suggestInteractive = widget.focusNode.hasFocus ||
        _suggestPanelGrace ||
        (widget.suggestionsAsOverlay && _overlayStayOpenUntilDismiss);
    final showAddFocused =
        widget.showAddRow && suggestInteractive && widget.onAddRow != null;
    final borderColor = widget.idleOutlineColor ?? Colors.grey.shade200;
    final media = MediaQuery.of(overlayCtx);
    final box =
        _fieldMeasureKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _suggestionOverlayEntry?.markNeedsBuild();
      });
      return const SizedBox.shrink();
    }
    final sz = box.size;
    final fieldTop = box.localToGlobal(Offset.zero).dy;
    final fieldBottom = fieldTop + sz.height;
    final kbBottom = media.viewInsets.bottom;
    final safeBottom = media.padding.bottom;
    final accessory = defaultTargetPlatform == TargetPlatform.iOS
        ? kMobileFormKeyboardAccessoryAllowance
        : 0.0;
    final usableBottom = media.size.height - kbBottom - safeBottom - accessory;
    final spaceBelowField = usableBottom - fieldBottom - 12;
    final capByScreen = media.size.height * 0.35;
    final double maxPanelH = math.max(
      120.0,
      math.min(
        math.min(widget.maxPanelAbs.toDouble(), capByScreen),
        math.max(120.0, spaceBelowField),
      ),
    );
    final showDivider = rows.isNotEmpty &&
        showAddFocused &&
        widget.onAddRow != null;
    final liveQ = widget.controller.text.trim().toLowerCase();
    final allHits = _allHitsForSheet(liveQ);
    final showSeeAll = allHits.length > rows.length;
    return CompositedTransformFollower(
      link: _layerLink,
      showWhenUnlinked: false,
      offset: Offset(0, sz.height + 4),
      child: TapRegion(
        groupId: _suggestionTapGroup,
        child: Material(
          elevation: 12,
          color: cs.surface,
          shadowColor: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: sz.width,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor.withValues(alpha: 0.45)),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxPanelH),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${rows.length} of ${allHits.length}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (showSeeAll)
                            TextButton(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () async {
                                await _openSeeAllSheet();
                                if (mounted) {
                                  _suggestionOverlayEntry?.markNeedsBuild();
                                }
                              },
                              child: const Text('See more'),
                            ),
                          IconButton(
                            tooltip: 'Close suggestions',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.close_rounded,
                              color: cs.onSurfaceVariant,
                            ),
                            onPressed: () {
                              _overlayStayOpenUntilDismiss = false;
                              widget.focusNode.unfocus();
                              FocusManager.instance.primaryFocus?.unfocus();
                              _removeSuggestionOverlay();
                              if (mounted) setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Scrollbar(
                        controller: _overlaySuggestScroll,
                        thumbVisibility: true,
                        interactive: true,
                        child: ListView(
                        controller: _overlaySuggestScroll,
                        shrinkWrap: false,
                        primary: false,
                        physics: const ClampingScrollPhysics(),
                        padding: EdgeInsets.zero,
                        clipBehavior: Clip.hardEdge,
                        children: [
                          for (final it in rows) _buildSuggestionTile(cs, it),
                          if (showDivider)
                            Divider(height: 1, thickness: 1, color: borderColor),
                          if (showAddFocused && widget.onAddRow != null)
                            _buildAddRowTile(cs),
                        ],
                      ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = _listRowsForUi();
    final suggestInteractive =
        widget.focusNode.hasFocus || _suggestPanelGrace;
    final showAddFocused =
        widget.showAddRow && suggestInteractive && widget.onAddRow != null;

    final lockLabel = widget.lockedSelectionLabel?.trim();
    final locked = lockLabel != null &&
        lockLabel.isNotEmpty &&
        !widget.focusNode.hasFocus;

    final hasPanelSource = !locked &&
        !_suppressPanelAfterPick &&
        suggestInteractive &&
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
          hintStyle: widget.hintStyle ??
              TextStyle(
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

    Widget fieldWrapped = innerInput;
    if (widget.suggestionsAsOverlay) {
      // Full-width target so the overlay matches the padded card, not only the inner input.
      fieldWrapped = CompositedTransformTarget(
        link: _layerLink,
        child: SizedBox(
          width: double.infinity,
          child: KeyedSubtree(
            key: _fieldMeasureKey,
            child: innerInput,
          ),
        ),
      );
    }

    final cardShadow = [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.08),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ];

    final subtree = KeyedSubtree(
      key: _revealKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          fieldWrapped,
          if (!widget.suggestionsAsOverlay && hasPanelSource) ...[
            const SizedBox(height: 8),
            Builder(
              builder: (ctx) {
                final liveQ = widget.controller.text.trim().toLowerCase();
                final allHits = _allHitsForSheet(liveQ);
                final showSeeAll = allHits.length > rows.length;
                final showDivider = rows.isNotEmpty &&
                    showAddFocused &&
                    widget.onAddRow != null;
                return DecoratedBox(
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
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${rows.length} of ${allHits.length}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (showSeeAll)
                                TextButton(
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                  ),
                                  onPressed: () async {
                                    await _openSeeAllSheet();
                                    if (ctx.mounted) setState(() {});
                                  },
                                  child: const Text('See more'),
                                ),
                              IconButton(
                                tooltip: 'Close suggestions',
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: cs.onSurfaceVariant,
                                ),
                                onPressed: () => widget.focusNode.unfocus(),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: widget.maxPanelAbs,
                          ),
                          child: Scrollbar(
                            controller: _inlineSuggestScroll,
                            thumbVisibility: true,
                            interactive: true,
                            child: ListView(
                              controller: _inlineSuggestScroll,
                              shrinkWrap: true,
                              primary: false,
                              physics: const ClampingScrollPhysics(),
                              padding: EdgeInsets.zero,
                              children: [
                                for (final it in rows)
                                  _buildSuggestionTile(cs, it),
                                if (showDivider)
                                  Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: borderColor,
                                  ),
                                if (showAddFocused && widget.onAddRow != null)
                                  _buildAddRowTile(cs),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
    if (widget.suggestionsAsOverlay) {
      _scheduleOverlaySync();
    } else if (_suggestionOverlayEntry != null) {
      _removeSuggestionOverlay();
    }
    // Do not dismiss on outside tap — only close icon, sheet barrier, or row pick.
    return TapRegion(
      groupId: _suggestionTapGroup,
      child: subtree,
    );
  }
}
