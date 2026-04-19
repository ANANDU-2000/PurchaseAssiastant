import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/search/catalog_fuzzy.dart';
import '../../core/theme/hexa_design_tokens.dart';

/// Single-select list with fuzzy search — tap row to `Navigator.pop(context, value)`.
///
/// Use for supplier, broker, category, etc. instead of cramped dropdowns.
Future<T?> showSearchPickerSheet<T>({
  required BuildContext context,
  required String title,
  required List<SearchPickerRow<T>> rows,
  T? selectedValue,
  List<Widget> Function(BuildContext sheetContext)? footerBuilder,
  double initialChildFraction = 0.72,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _SearchPickerBody<T>(
      title: title,
      rows: rows,
      selectedValue: selectedValue,
      footerBuilder: footerBuilder,
      initialChildFraction: initialChildFraction,
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

  String get haystack =>
      '$title ${subtitle ?? ''}'.trim();
}

class _SearchPickerBody<T> extends StatefulWidget {
  const _SearchPickerBody({
    required this.title,
    required this.rows,
    this.selectedValue,
    this.footerBuilder,
    required this.initialChildFraction,
  });

  final String title;
  final List<SearchPickerRow<T>> rows;
  final T? selectedValue;
  final List<Widget> Function(BuildContext sheetContext)? footerBuilder;
  final double initialChildFraction;

  @override
  State<_SearchPickerBody<T>> createState() => _SearchPickerBodyState<T>();
}

class _SearchPickerBodyState<T> extends State<_SearchPickerBody<T>> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final h = mq.size.height * widget.initialChildFraction;
    final q = _q.text.trim();
    final minFuzzy = q.length <= 1 ? 10.0 : 18.0;
    final filtered = q.isEmpty
        ? widget.rows
        : catalogFuzzyRank(
            q,
            widget.rows,
            (r) => r.haystack,
            minScore: minFuzzy,
            limit: 400,
          );
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
                  onChanged: (_) => setState(() {}),
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
                    child: filtered.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                q.isEmpty ? 'Nothing to show.' : 'No matches for “$q”.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final r = filtered[i];
                              final sel = widget.selectedValue == r.value;
                              return ListTile(
                                selected: sel,
                                title: Text(
                                  r.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                subtitle: r.subtitle == null || r.subtitle!.isEmpty
                                    ? null
                                    : Text(
                                        r.subtitle!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                trailing: sel
                                    ? Icon(Icons.check_rounded,
                                        color: Theme.of(context).colorScheme.primary)
                                    : null,
                                onTap: () => Navigator.pop(context, r.value),
                              );
                            },
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
