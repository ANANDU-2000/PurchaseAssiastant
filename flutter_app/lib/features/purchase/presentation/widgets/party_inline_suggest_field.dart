import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/widgets/inline_search_field.dart';

/// Party step only: dropdown suggestions **below** the field (no overlay), max height 250.
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

  void _listenCtrl() => setState(() {});

  void _listenFocus() {
    if (!widget.focusNode.hasFocus) _tryBlurExactPick();
    setState(() {});
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
    return EdgeInsets.only(bottom: 24 + kb);
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
    final showAddFocused =
        widget.showAddRow && widget.focusNode.hasFocus && widget.onAddRow != null;
    final hasPanel =
        widget.focusNode.hasFocus && (rows.isNotEmpty || showAddFocused);

    final borderColor = Colors.grey.shade300;
    final borderRadiusBottom = hasPanel ? 0.0 : 8.0;
    final vPad = widget.dense ? 8.0 : 10.0;
    final hPad = widget.dense ? 8.0 : 10.0;

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
          filled: true,
          fillColor: Colors.grey.shade50,
          contentPadding:
              EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(8),
              bottom: Radius.circular(borderRadiusBottom),
            ),
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(8),
              bottom: Radius.circular(borderRadiusBottom),
            ),
            borderSide: BorderSide(color: cs.primary, width: 2),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: borderColor),
          ),
        ),
      ),
    );

    if (!hasPanel) return field;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(
              left: BorderSide(color: borderColor),
              right: BorderSide(color: borderColor),
              bottom: BorderSide(color: borderColor),
            ),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(8),
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 250),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(7),
              ),
              child: ListView(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.zero,
                children: [
                  for (final it in rows)
                    InkWell(
                      onTap: () => _pick(it),
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
                  if (widget.showAddRow &&
                      widget.onAddRow != null &&
                      rows.isNotEmpty)
                    Divider(height: 1, thickness: 1, color: borderColor),
                  if (showAddFocused && widget.onAddRow != null)
                    InkWell(
                      onTap: widget.onAddRow,
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
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
