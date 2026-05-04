import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is InlineSearchItem && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Inline search with [RawAutocomplete] overlay (max height 200, scrollable).
///
/// * Enter auto-picks when exactly one option matches the current query.
/// * Blur auto-picks when typed text matches exactly one item (case-insensitive).
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
  late final TextEditingController _ctrl = widget.controller ??
      TextEditingController(text: widget.initialLabel ?? '');
  late final FocusNode _ownedFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;
  bool get _disposeFocus => widget.focusNode == null;

  bool _pickInProgress = false;
  String? _lastPickFingerprint;
  int _lastPickMs = 0;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    _ctrl.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    if (_disposeFocus) _ownedFocus.dispose();
    if (widget.controller == null) _ctrl.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    if (_focus.hasFocus) return;
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
    if (mounted) setState(() {});
  }

  bool _consumeIfDuplicatePick(InlineSearchItem it) {
    final fp = '${it.id}\u241e${it.label}';
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastPickFingerprint == fp && now - _lastPickMs < 400) return true;
    _lastPickFingerprint = fp;
    _lastPickMs = now;
    return false;
  }

  Iterable<InlineSearchItem> _optionsForQuery(String raw) {
    final q = raw.trim().toLowerCase();
    final min = widget.minQueryLength.clamp(1, 64);
    if (q.isEmpty || q.length < min) return const [];
    final out = <InlineSearchItem>[];
    for (final it in widget.items) {
      if (out.length >= 8) break;
      final lab = it.label.toLowerCase();
      final sub = (it.subtitle ?? '').toLowerCase();
      if (lab.contains(q) || sub.contains(q)) out.add(it);
    }
    return out;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final opts = _optionsForQuery(_ctrl.text).toList();
      if (opts.length == 1) {
        _pick(opts.first, keepFocus: false);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _pick(InlineSearchItem it, {bool keepFocus = true}) {
    if (_consumeIfDuplicatePick(it)) return;
    _pickInProgress = true;
    final label = it.label;
    _ctrl.value = TextEditingValue(
      text: label,
      selection: TextSelection.collapsed(offset: label.length),
    );
    if (!mounted) {
      _pickInProgress = false;
      return;
    }
    setState(() {});
    try {
      if (kDebugMode) {
        debugPrint('[InlineSearch] pick id="${it.id}" label="$label"');
      }
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

  double _optionsMaxHeight(BuildContext context) {
    final mq = MediaQuery.of(context);
    final usable = mq.size.height -
        mq.viewInsets.bottom -
        mq.padding.vertical;
    final v = math.max(120.0, usable * 0.42);
    return math.min(200.0, v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        RawAutocomplete<InlineSearchItem>(
          focusNode: _focus,
          textEditingController: _ctrl,
          displayStringForOption: (InlineSearchItem o) => o.label,
          optionsBuilder: (TextEditingValue tev) {
            return _optionsForQuery(tev.text);
          },
          onSelected: (InlineSearchItem it) => _pick(it, keepFocus: false),
          fieldViewBuilder: (
            BuildContext context,
            TextEditingController textEditingController,
            FocusNode focusNode,
            VoidCallback onFieldSubmitted,
          ) {
            return Focus(
              onKeyEvent: _onKey,
              child: TextField(
                controller: textEditingController,
                focusNode: focusNode,
                textInputAction:
                    widget.textInputAction ?? TextInputAction.search,
                onSubmitted: (_) {
                  final opts =
                      _optionsForQuery(textEditingController.text).toList();
                  if (opts.length == 1) {
                    _pick(opts.first, keepFocus: false);
                  } else {
                    onFieldSubmitted();
                  }
                },
                decoration: InputDecoration(
                  hintText: widget.placeholder,
                  prefixIcon: widget.prefixIcon,
                  suffixIcon: textEditingController.text.isEmpty
                      ? const Icon(Icons.search_rounded, size: 22)
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () {
                            textEditingController.clear();
                            setState(() {});
                          },
                        ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                ),
              ),
            );
          },
          optionsViewBuilder: (
            BuildContext context,
            AutocompleteOnSelected<InlineSearchItem> onSelected,
            Iterable<InlineSearchItem> options,
          ) {
            final opts = options.toList();
            if (opts.isEmpty) return const SizedBox.shrink();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                color: Colors.white,
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(maxHeight: _optionsMaxHeight(context)),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    physics: const ClampingScrollPhysics(),
                    itemCount: opts.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.grey[200],
                    ),
                    itemBuilder: (BuildContext ctx, int i) {
                      final it = opts[i];
                      void commit() => onSelected(it);
                      return Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (PointerDownEvent e) {
                          if (e.buttons != 0 &&
                              (e.buttons & kPrimaryButton) == 0) {
                            return;
                          }
                          commit();
                        },
                        child: InkWell(
                          onTap: commit,
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
                                        color: Theme.of(ctx)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
