import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/search/catalog_fuzzy.dart';
import '../../core/search/search_highlight.dart';
import '../../core/theme/hexa_design_tokens.dart';

/// Single-select list with fuzzy search — tap row to `Navigator.pop(context, value)`.
///
/// [pinnedRows] show first when the query is empty (e.g. recent suppliers).
/// Query is debounced by [queryDebounce] before filtering (default 150ms).
Future<T?> showSearchPickerSheet<T>({
  required BuildContext context,
  required String title,
  required List<SearchPickerRow<T>> rows,
  T? selectedValue,
  List<SearchPickerRow<T>>? pinnedRows,
  List<Widget> Function(BuildContext sheetContext)? footerBuilder,
  double initialChildFraction = 0.72,
  Duration queryDebounce = const Duration(milliseconds: 150),
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _SearchPickerBody<T>(
      title: title,
      rows: rows,
      pinnedRows: pinnedRows,
      selectedValue: selectedValue,
      footerBuilder: footerBuilder,
      initialChildFraction: initialChildFraction,
      queryDebounce: queryDebounce,
    ),
  );
}

class SearchPickerRow<T> {
  const SearchPickerRow({
    required this.value,
    required this.title,
    this.subtitle,
  });

  final T value;
  final String title;
  final String? subtitle;

  String get haystack => '$title ${subtitle ?? ''}'.trim();
}

class _SearchPickerBody<T> extends StatefulWidget {
  const _SearchPickerBody({
    required this.title,
    required this.rows,
    this.pinnedRows,
    this.selectedValue,
    this.footerBuilder,
    required this.initialChildFraction,
    required this.queryDebounce,
  });

  final String title;
  final List<SearchPickerRow<T>> rows;
  final List<SearchPickerRow<T>>? pinnedRows;
  final T? selectedValue;
  final List<Widget> Function(BuildContext sheetContext)? footerBuilder;
  final double initialChildFraction;
  final Duration queryDebounce;

  @override
  State<_SearchPickerBody<T>> createState() => _SearchPickerBodyState<T>();
}

class _SearchPickerBodyState<T> extends State<_SearchPickerBody<T>> {
  final _q = TextEditingController();
  Timer? _debounce;
  String _debouncedQuery = '';

  @override
  void initState() {
    super.initState();
    _debouncedQuery = _q.text;
    _q.addListener(_onQueryTick);
  }

  void _onQueryTick() {
    _debounce?.cancel();
    _debounce = Timer(widget.queryDebounce, () {
      if (!mounted) return;
      setState(() => _debouncedQuery = _q.text);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.removeListener(_onQueryTick);
    _q.dispose();
    super.dispose();
  }

  List<SearchPickerRow<T>> _rowsForQuery() {
    final q = _debouncedQuery.trim();
    final pinned = widget.pinnedRows ?? <SearchPickerRow<T>>[];
    if (q.isEmpty) {
      if (pinned.isEmpty) return widget.rows;
      final seen = <T>{};
      for (final p in pinned) {
        seen.add(p.value);
      }
      final tail = widget.rows.where((r) => !seen.contains(r.value)).toList();
      return <SearchPickerRow<T>>[...pinned, ...tail];
    }
    final minFuzzy = q.length <= 1 ? 10.0 : 18.0;
    return catalogFuzzyRank(
      q,
      widget.rows,
      (r) => r.haystack,
      minScore: minFuzzy,
      limit: 400,
    );
  }

  List<Widget> _buildListTiles(BuildContext context, List<SearchPickerRow<T>> rows) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final baseTitle = tt.bodyLarge?.copyWith(fontWeight: FontWeight.w700) ??
        const TextStyle(fontWeight: FontWeight.w700);
    final hiTitle = baseTitle.copyWith(
      color: cs.primary,
      fontWeight: FontWeight.w800,
      backgroundColor: cs.primaryContainer.withValues(alpha: 0.35),
    );
    final baseSub = tt.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final hiSub = baseSub?.copyWith(
      color: cs.primary,
      fontWeight: FontWeight.w600,
      backgroundColor: cs.primaryContainer.withValues(alpha: 0.25),
    );

    final q = _debouncedQuery.trim();
    final pinnedVals = (widget.pinnedRows ?? <SearchPickerRow<T>>[])
        .map((e) => e.value)
        .toSet();
    final children = <Widget>[];
    var addedRecent = false;
    var addedAll = false;

    for (final r in rows) {
      if (q.isEmpty && pinnedVals.isNotEmpty && pinnedVals.contains(r.value)) {
        if (!addedRecent) {
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                'Recent',
                style: tt.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          );
          addedRecent = true;
        }
      } else if (q.isEmpty && pinnedVals.isNotEmpty && !pinnedVals.contains(r.value)) {
        if (!addedAll) {
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text(
                'All',
                style: tt.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          );
          addedAll = true;
        }
      }

      final sel = widget.selectedValue == r.value;
      final isPinnedRow = q.isEmpty && pinnedVals.contains(r.value);
      children.add(
        ListTile(
          selected: sel,
          leading: isPinnedRow
              ? Icon(Icons.history_rounded, size: 20, color: cs.onSurfaceVariant)
              : null,
          title: Text.rich(
            TextSpan(
              children: highlightSearchQuery(
                r.title,
                q,
                baseStyle: baseTitle,
                highlightStyle: hiTitle,
              ),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: r.subtitle == null || r.subtitle!.isEmpty
              ? null
              : Text.rich(
                  TextSpan(
                    children: highlightSearchQuery(
                      r.subtitle!,
                      q,
                      baseStyle: baseSub ?? const TextStyle(),
                      highlightStyle: hiSub ?? baseSub ?? const TextStyle(),
                    ),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: sel
              ? Icon(Icons.check_rounded, color: cs.primary)
              : null,
          onTap: () => Navigator.pop(context, r.value),
        ),
      );
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final h = mq.size.height * widget.initialChildFraction;
    final q = _debouncedQuery.trim();
    final rowsToShow = _rowsForQuery();
    final listMaxH = math
        .min(HexaDesignTokens.suggestionsMaxHeight, h - 168)
        .clamp(120.0, HexaDesignTokens.suggestionsMaxHeight);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: SizedBox(
          height: h,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  widget.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _q,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Type to search…',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (widget.footerBuilder != null)
                ...widget.footerBuilder!(context),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: listMaxH),
                    child: rowsToShow.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                q.isEmpty ? 'Nothing to show.' : 'No matches for “$q”.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView(
                            shrinkWrap: true,
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                            children: _buildListTiles(context, rowsToShow),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
