import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/analytics_breakdown_providers.dart';
import '../../../core/providers/reports_filtered_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../filters/reports_filter_state.dart';

/// Open filter drawer (mobile end-drawer or desktop panel).
Future<void> showReportsFilterPanel({
  required BuildContext context,
  required WidgetRef ref,
}) {
  final wide = MediaQuery.sizeOf(context).width >= 1024;
  if (wide) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Filters',
      pageBuilder: (ctx, _, __) => Align(
        alignment: Alignment.centerRight,
        child: Material(
          elevation: 8,
          child: SizedBox(
            width: 360,
            height: MediaQuery.sizeOf(ctx).height,
            child: ReportsFilterPanelBody(onClose: () => Navigator.pop(ctx)),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scroll) => ReportsFilterPanelBody(
        scrollController: scroll,
        onClose: () => Navigator.pop(ctx),
      ),
    ),
  );
}

class ReportsFilterPanelBody extends ConsumerStatefulWidget {
  const ReportsFilterPanelBody({
    super.key,
    this.scrollController,
    required this.onClose,
  });

  final ScrollController? scrollController;
  final VoidCallback onClose;

  @override
  ConsumerState<ReportsFilterPanelBody> createState() =>
      _ReportsFilterPanelBodyState();
}

class _ReportsFilterPanelBodyState extends ConsumerState<ReportsFilterPanelBody> {
  late ReportsFilterState _draft;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(reportsFilterProvider);
  }

  void _apply() {
    ref.read(reportsFilterProvider.notifier).apply(_draft);
    widget.onClose();
  }

  void _reset() {
    ref.read(reportsFilterProvider.notifier).reset();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(analyticsCategoriesTableProvider).valueOrNull ?? [];
    final types = ref.watch(analyticsTypesTableProvider).valueOrNull ?? [];
    final suppliers =
        ref.watch(analyticsSuppliersTableProvider).valueOrNull ?? [];
    final filtered = ref.watch(reportsFilteredDataProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Filters',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              _section(
                title: 'Units',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final u in ReportsUnitFilter.values)
                      FilterChip(
                        label: Text(u.name.toUpperCase()),
                        selected: _draft.units.contains(u),
                        onSelected: (sel) => setState(() {
                          if (u == ReportsUnitFilter.all) {
                            _draft = _draft.copyWith(
                              units: sel ? {ReportsUnitFilter.all} : {},
                            );
                          } else {
                            final next = Set<ReportsUnitFilter>.from(
                              _draft.units,
                            )..remove(ReportsUnitFilter.all);
                            if (sel) {
                              next.add(u);
                            } else {
                              next.remove(u);
                            }
                            if (next.isEmpty) next.add(ReportsUnitFilter.all);
                            _draft = _draft.copyWith(units: next);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              _section(
                title: 'Category',
                child: _idChips(
                  items: cats
                      .map(
                        (c) => (
                          id: (c['category_id'] ?? c['id'] ?? c['category_name'])
                              .toString(),
                          label: (c['category_name'] ?? c['category'] ?? '—')
                              .toString(),
                        ),
                      )
                      .toList(),
                  selected: _draft.categoryIds,
                  onChanged: (ids) =>
                      setState(() => _draft = _draft.copyWith(categoryIds: ids)),
                ),
              ),
              _section(
                title: 'Subcategory',
                child: _idChips(
                  items: types
                      .map(
                        (c) => (
                          id: (c['type_id'] ?? c['id'] ?? c['type_name'])
                              .toString(),
                          label: (c['type_name'] ?? c['subcategory'] ?? '—')
                              .toString(),
                        ),
                      )
                      .toList(),
                  selected: _draft.subcategoryIds,
                  onChanged: (ids) => setState(
                    () => _draft = _draft.copyWith(subcategoryIds: ids),
                  ),
                ),
              ),
              _section(
                title: 'Supplier',
                child: _idChips(
                  items: suppliers
                      .map(
                        (s) => (
                          id: (s['supplier_id'] ?? s['id'] ?? s['supplier_name'])
                              .toString(),
                          label: (s['supplier_name'] ?? s['name'] ?? '—')
                              .toString(),
                        ),
                      )
                      .toList(),
                  selected: _draft.supplierIds,
                  onChanged: (ids) =>
                      setState(() => _draft = _draft.copyWith(supplierIds: ids)),
                ),
              ),
              _section(
                title: 'Broker',
                child: _idChips(
                  items: filtered.brokers
                      .map((b) => (id: b.key, label: b.name))
                      .toList(),
                  selected: _draft.brokerIds,
                  onChanged: (ids) =>
                      setState(() => _draft = _draft.copyWith(brokerIds: ids)),
                ),
              ),
              _section(
                title: 'Usage',
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final u in ReportsUsageFilter.values)
                      FilterChip(
                        label: Text(switch (u) {
                          ReportsUsageFilter.all => 'All items',
                          ReportsUsageFilter.usageOnly => 'Daily usage',
                          ReportsUsageFilter.excludeUsage => 'Exclude usage',
                        }),
                        selected: _draft.usage == u,
                        onSelected: (_) =>
                            setState(() => _draft = _draft.copyWith(usage: u)),
                      ),
                  ],
                ),
              ),
              _section(
                title: 'Sort',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in ReportsSort.values)
                      FilterChip(
                        label: Text(switch (s) {
                          ReportsSort.latest => 'Latest',
                          ReportsSort.highestQty => 'High qty',
                          ReportsSort.highestValue => 'High value',
                          ReportsSort.az => 'A–Z',
                        }),
                        selected: _draft.sort == s,
                        onSelected: (_) =>
                            setState(() => _draft = _draft.copyWith(sort: s)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _reset,
                  child: const Text('Reset all'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _apply,
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section({required String title, required Widget child}) {
    return ExpansionTile(
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
      initiallyExpanded: title == 'Units' || title == 'Sort',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: child,
        ),
      ],
    );
  }

  Widget _idChips({
    required List<({String id, String label})> items,
    required Set<String> selected,
    required ValueChanged<Set<String>> onChanged,
  }) {
    if (items.isEmpty) {
      return const Text(
        'No options in this period.',
        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final item in items.take(24))
          FilterChip(
            label: Text(item.label, overflow: TextOverflow.ellipsis),
            selected: selected.contains(item.id),
            onSelected: (sel) {
              final next = Set<String>.from(selected);
              if (sel) {
                next.add(item.id);
              } else {
                next.remove(item.id);
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}

/// Desktop persistent filter drawer summary.
class ReportsFilterDrawer extends ConsumerWidget {
  const ReportsFilterDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(reportsFilterProvider);
    return Material(
      color: HexaColors.brandCard,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Filters',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            '${filters.activeCount} active',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => showReportsFilterPanel(context: context, ref: ref),
            child: const Text('Edit filters'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => ref.read(reportsFilterProvider.notifier).reset(),
            child: const Text('Reset all'),
          ),
        ],
      ),
    );
  }
}

/// Legacy alias — redirects to new panel.
Future<void> showReportsFilterSheet({
  required BuildContext context,
  required WidgetRef ref,
}) =>
    showReportsFilterPanel(context: context, ref: ref);