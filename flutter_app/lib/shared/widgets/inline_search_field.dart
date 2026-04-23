import 'dart:async';

import 'package:flutter/material.dart';

/// One selectable option for [InlineSearchField].
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

/// Tally-style fuzzy picker: suggestions render under the field (no new route).
class InlineSearchField extends StatefulWidget {
  const InlineSearchField({
    super.key,
    required this.items,
    required this.onSelected,
    this.controller,
    this.placeholder,
    this.initialLabel,
    this.prefixIcon,
    /// After choosing a suggestion, move focus here (e.g. qty) — Tally-style flow.
    this.focusAfterSelection,
    this.textInputAction,
    /// Optional; use to chain focus from another field (e.g. supplier → item search).
    this.focusNode,
    /// Minimum query length before suggestions run (reduces lag on large catalogs).
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
  Timer? _debounce;
  List<InlineSearchItem> _suggestions = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) {
      setState(() => _showSuggestions = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.removeListener(_onFocusChange);
    if (_disposeFocus) {
      _ownedFocus.dispose();
    }
    if (widget.controller == null) {
      _ctrl.dispose();
    }
    super.dispose();
  }

  void _scheduleFilter(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      final query = q.trim().toLowerCase();
      if (query.isEmpty ||
          query.length < widget.minQueryLength.clamp(1, 64)) {
        setState(() {
          _suggestions = [];
          _showSuggestions = false;
        });
        return;
      }
      final out = <InlineSearchItem>[];
      for (final it in widget.items) {
        if (out.length >= 5) break;
        final lab = it.label.toLowerCase();
        final sub = (it.subtitle ?? '').toLowerCase();
        if (lab.contains(query) || sub.contains(query)) {
          out.add(it);
        }
      }
      if (!mounted) return;
      setState(() {
        _suggestions = out;
        _showSuggestions = _focus.hasFocus && out.isNotEmpty;
      });
    });
  }

  void _pick(InlineSearchItem it) {
    _ctrl.text = it.label;
    widget.onSelected(it);
    setState(() {
      _suggestions = [];
      _showSuggestions = false;
    });
    final next = widget.focusAfterSelection;
    if (next != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        next.requestFocus();
      });
    } else {
      _focus.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _ctrl,
          focusNode: _focus,
          textInputAction: widget.textInputAction ?? TextInputAction.next,
          onChanged: (v) {
            _scheduleFilter(v);
            // Do not set [_showSuggestions] from stale [_suggestions] here; the debounced
            // [_scheduleFilter] is the single source of truth.
          },
          onTap: () {
            _scheduleFilter(_ctrl.text);
          },
          decoration: InputDecoration(
            hintText: widget.placeholder,
            prefixIcon: widget.prefixIcon,
            suffixIcon: const Icon(Icons.search_rounded, size: 22),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
        if (_showSuggestions && _suggestions.isNotEmpty)
          Material(
            clipBehavior: Clip.antiAlias,
            elevation: 3,
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (context, i) {
                  final it = _suggestions[i];
                  return InkWell(
                    onTap: () => _pick(it),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            it.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (it.subtitle != null &&
                              it.subtitle!.trim().isNotEmpty)
                            Text(
                              it.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
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
      ],
    );
  }
}
