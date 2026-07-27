import 'package:flutter/material.dart';

import '../../../core/theme/hexa_colors.dart';

/// Searchable chip list with expand/collapse (avoids filter sheet overflow).
class ReportsFilterSearchSection extends StatefulWidget {
  const ReportsFilterSearchSection({
    super.key,
    required this.title,
    required this.hint,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.initiallyExpanded = true,
    this.collapsedVisible = 8,
  });

  final String title;
  final String hint;
  final List<({String id, String label})> items;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool initiallyExpanded;
  final int collapsedVisible;

  @override
  State<ReportsFilterSearchSection> createState() =>
      _ReportsFilterSearchSectionState();
}

class _ReportsFilterSearchSectionState extends State<ReportsFilterSearchSection> {
  final _searchCtl = TextEditingController();
  bool _expanded = false;
  bool _sectionOpen = true;

  @override
  void initState() {
    super.initState();
    _sectionOpen = widget.initiallyExpanded;
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  List<({String id, String label})> get _filtered {
    final q = _searchCtl.text.trim().toLowerCase();
    if (q.isEmpty) return widget.items;
    return widget.items
        .where((e) => e.label.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final showAll = _expanded || list.length <= widget.collapsedVisible;
    final visible = showAll ? list : list.take(widget.collapsedVisible).toList();
    final hidden = list.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _sectionOpen = !_sectionOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (widget.selected.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: HexaColors.brandPrimary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${widget.selected.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: HexaColors.brandPrimary,
                      ),
                    ),
                  ),
                Icon(
                  _sectionOpen
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 22,
                  color: HexaColors.brandPrimary,
                ),
              ],
            ),
          ),
        ),
        if (_sectionOpen) ...[
          TextField(
            controller: _searchCtl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: widget.hint,
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchCtl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _searchCtl.clear();
                        setState(() {});
                      },
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 8),
          if (list.isEmpty)
            const Text(
              'No matches.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in visible)
                  FilterChip(
                    label: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: widget.selected.contains(item.id),
                    onSelected: (sel) {
                      final next = Set<String>.from(widget.selected);
                      if (sel) {
                        next.add(item.id);
                      } else {
                        next.remove(item.id);
                      }
                      widget.onChanged(next);
                    },
                  ),
              ],
            ),
          if (!showAll && hidden > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _expanded = true),
                child: Text('Show all ($hidden more)'),
              ),
            )
          else if (_expanded && list.length > widget.collapsedVisible)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _expanded = false),
                child: const Text('Show less'),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
