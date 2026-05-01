import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A selectable option for [InlineSearchField].
class InlineSearchItem {
  const InlineSearchItem({
    required this.id,
    required this.label,
    this.subtitle,
  });

  final String id;
  final String label;
  final String? subtitle;
}

/// Simple inline-only search field. Suggestions render directly below the
/// input in the same widget tree — no [Overlay], no focus race with
/// [Flutter Web's] pointer/focus ordering.
///
/// Extras that make it forgiving:
/// * Enter auto-picks the single visible suggestion.
/// * Blur auto-picks when the typed text matches exactly one item (case-insensitive).
class InlineSearchField extends StatefulWidget {
  const InlineSearchField({
    super.key,
    required this.items,
    required this.onSelected,
    this.controller,
    this.placeholder,
    this.initialLabel,
    this.prefixIcon,
    this.focusAfterSelection,
    this.textInputAction,
    this.focusNode,
    this.minQueryLength = 1,
  });

  final List<InlineSearchItem> items;
  final int minQueryLength;
  final void Function(InlineSearchItem item) onSelected;
  final TextEditingController? controller;
  final String? placeholder;
  final String? initialLabel;
  final Widget? prefixIcon;
  final FocusNode? focusAfterSelection;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;

  @override
  State<InlineSearchField> createState() => _InlineSearchFieldState();
}

class _InlineSearchFieldState extends State<InlineSearchField> {
  late final TextEditingController _ctrl =
      widget.controller ?? TextEditingController(text: widget.initialLabel ?? '');
  late final FocusNode _ownedFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;
  bool get _disposeFocus => widget.focusNode == null;

  final GlobalKey _targetKey = GlobalKey();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  Timer? _debounce;
  List<InlineSearchItem> _suggestions = const [];
  bool _showSuggestions = false;
  /// True while [_pick] is committing a selection, so the blur listener does
  /// not try to also commit a fuzzy match on the stale typed text.
  bool _pickInProgress = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    _ctrl.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    _focus.removeListener(_onFocusChange);
    _ctrl.removeListener(_onControllerChanged);
    if (_disposeFocus) _ownedFocus.dispose();
    if (widget.controller == null) _ctrl.dispose();
    super.dispose();
  }

  /// Keeps the clear/search suffix and the suggestions panel in sync when the
  /// controller is mutated externally (parent clears it, [_pick] sets it).
  void _onControllerChanged() {
    if (!mounted) return;
    if (_ctrl.text.isEmpty && _showSuggestions) {
      setState(() {
        _suggestions = const [];
        _showSuggestions = false;
      });
      _syncOverlay();
    } else {
      setState(() {});
      _syncOverlay();
    }
  }

  void _onFocusChange() {
    if (!mounted) return;
    if (_focus.hasFocus) {
      // Re-show matches when user refocuses with existing text.
      _runFilter(_ctrl.text, showEvenIfEmptyQuery: false);
      return;
    }
    // On blur: try to auto-pick if typed text uniquely matches one item.
    if (!_pickInProgress) {
      final q = _ctrl.text.trim().toLowerCase();
      if (q.isNotEmpty) {
        final exact = <InlineSearchItem>[];
        for (final it in widget.items) {
          if (it.label.toLowerCase() == q) {
            exact.add(it);
            if (exact.length > 1) break;
          }
        }
        if (exact.length == 1) {
          _pick(exact.first, keepFocus: false);
          return;
        }
      }
    }
    if (mounted) {
      setState(() {
        _showSuggestions = false;
      });
    }
    _syncOverlay();
  }

  void _runFilter(String raw, {bool showEvenIfEmptyQuery = false}) {
    final q = raw.trim().toLowerCase();
    final min = widget.minQueryLength.clamp(1, 64);
    if (q.isEmpty || q.length < min) {
      if (!mounted) return;
      setState(() {
        _suggestions = const [];
        _showSuggestions = showEvenIfEmptyQuery;
      });
      _syncOverlay();
      return;
    }
    final out = <InlineSearchItem>[];
    for (final it in widget.items) {
      if (out.length >= 8) break;
      final lab = it.label.toLowerCase();
      final sub = (it.subtitle ?? '').toLowerCase();
      if (lab.contains(q) || sub.contains(q)) out.add(it);
    }
    if (!mounted) return;
    setState(() {
      _suggestions = out;
      _showSuggestions = out.isNotEmpty && _focus.hasFocus;
    });
    _syncOverlay();
  }

  void _onChangedDebounced(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      _runFilter(v);
    });
  }

  void _onFieldTap() {
    _runFilter(_ctrl.text);
  }

  /// Handle Enter: if exactly one suggestion is visible, pick it.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_showSuggestions && _suggestions.length == 1) {
        _pick(_suggestions.first);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _pick(InlineSearchItem it, {bool keepFocus = true}) {
    _pickInProgress = true;
    _debounce?.cancel();
    _ctrl.text = it.label;
    _ctrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _ctrl.text.length),
    );
    if (!mounted) {
      _pickInProgress = false;
      return;
    }
    setState(() {
      _suggestions = const [];
      _showSuggestions = false;
    });
    _syncOverlay();
    try {
      widget.onSelected(it);
    } finally {
      _pickInProgress = false;
    }
    final next = widget.focusAfterSelection;
    if (next != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) next.requestFocus();
      });
    } else if (!keepFocus) {
      _focus.unfocus();
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _syncOverlay() {
    if (!mounted) return;
    if (!_showSuggestions || _suggestions.isEmpty || !_focus.hasFocus) {
      _removeOverlay();
      return;
    }

    final overlay = Overlay.of(context);

    var showAbove = false;
    try {
      final ctx = _targetKey.currentContext;
      final rb = ctx?.findRenderObject();
      if (rb is RenderBox && rb.hasSize) {
        final pos = rb.localToGlobal(Offset.zero);
        final fieldBottom = pos.dy + rb.size.height;
        final media = MediaQuery.of(context);
        final keyboardTop = media.size.height - media.viewInsets.bottom;
        final spaceBelow = keyboardTop - fieldBottom - 8;
        showAbove = spaceBelow < 160;
      }
    } catch (_) {}

    if (_overlayEntry == null) {
      _overlayEntry = OverlayEntry(
        builder: (ctx) => _InlineSearchOverlay(
            link: _layerLink,
            showAbove: showAbove,
            suggestions: _suggestions,
            onPick: (it) => _pick(it),
          ),
      );
      overlay.insert(_overlayEntry!);
    } else {
      _overlayEntry!.markNeedsBuild();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Focus(
          onKeyEvent: _onKey,
          child: CompositedTransformTarget(
            link: _layerLink,
            child: KeyedSubtree(
              key: _targetKey,
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                textInputAction: widget.textInputAction ?? TextInputAction.search,
                onChanged: _onChangedDebounced,
                onTap: _onFieldTap,
                decoration: InputDecoration(
                  hintText: widget.placeholder,
                  prefixIcon: widget.prefixIcon,
                  suffixIcon: _ctrl.text.isEmpty
                      ? const Icon(Icons.search_rounded, size: 22)
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () {
                            _ctrl.clear();
                            setState(() {
                              _suggestions = const [];
                              _showSuggestions = false;
                            });
                            _syncOverlay();
                          },
                        ),
                  isDense: true,
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: cs.primary, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InlineSearchOverlay extends StatelessWidget {
  const _InlineSearchOverlay({
    required this.link,
    required this.showAbove,
    required this.suggestions,
    required this.onPick,
  });

  final LayerLink link;
  final bool showAbove;
  final List<InlineSearchItem> suggestions;
  final void Function(InlineSearchItem it) onPick;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme;

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Stack(
          children: [
            // Tap-away to dismiss keyboard/suggestions.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              ),
            ),
            CompositedTransformFollower(
              link: link,
              showWhenUnlinked: false,
              targetAnchor: showAbove ? Alignment.topLeft : Alignment.bottomLeft,
              followerAnchor: showAbove ? Alignment.bottomLeft : Alignment.topLeft,
              offset: showAbove ? const Offset(0, -8) : const Offset(0, 8),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                color: Colors.white,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: suggestions.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.grey[200],
                    ),
                    itemBuilder: (ctx, i) {
                      final it = suggestions[i];
                      return Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (_) => onPick(it),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
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
                                  fontSize: 14,
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
                                      fontSize: 12,
                                      color: accent.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
