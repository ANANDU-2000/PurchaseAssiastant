import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/widgets/friendly_load_error.dart';

import '../../../../core/theme/hexa_colors.dart';
enum _TimelineKindFilter {
  all,
  purchase,
  adjustment,
  transfer,
  sale,
  physical,
}

/// Movement / activity timeline for an item (purchases, adjustments, sales…).
class ItemTimelineSection extends ConsumerStatefulWidget {
  const ItemTimelineSection({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<ItemTimelineSection> createState() =>
      _ItemTimelineSectionState();
}

class _ItemTimelineSectionState extends ConsumerState<ItemTimelineSection> {
  _TimelineKindFilter _kind = _TimelineKindFilter.all;
  final _searchCtrl = TextEditingController();
  int _visibleLimit = 12;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesKind(Map row) {
    final kind = (row['kind'] ?? row['type'] ?? row['activity_kind'])
            ?.toString()
            .trim()
            .toLowerCase() ??
        '';
    final title = (row['title'] ?? '').toString().toLowerCase();
    switch (_kind) {
      case _TimelineKindFilter.all:
        return true;
      case _TimelineKindFilter.purchase:
        return kind.contains('purchase') ||
            kind.contains('delivery') ||
            title.contains('purchase');
      case _TimelineKindFilter.adjustment:
        return kind.contains('correction') ||
            kind.contains('adjust') ||
            kind.contains('damage') ||
            kind.contains('wastage') ||
            title.contains('adjust') ||
            title.contains('correction');
      case _TimelineKindFilter.transfer:
        return kind.contains('transfer') || title.contains('transfer');
      case _TimelineKindFilter.sale:
        return kind.contains('sale') || title.contains('sale');
      case _TimelineKindFilter.physical:
        return kind.contains('physical') ||
            kind.contains('count') ||
            title.contains('physical');
    }
  }

  bool _matchesSearch(Map row, String q) {
    if (q.isEmpty) return true;
    final hay = [
      row['title'],
      row['actor_name'],
      row['kind'],
      row['notes'],
      row['reason'],
    ].map((e) => e?.toString().toLowerCase() ?? '').join(' ');
    return hay.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(stockItemActivityProvider(widget.itemId));
    final session = ref.watch(sessionProvider);
    final warehouse =
        session?.primaryBusiness.effectiveDisplayTitle.trim() ?? '';
    final q = _searchCtrl.text.trim().toLowerCase();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(HexaOp.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Timeline', style: HexaOp.cardTitle(context)),
                ),
                TextButton(
                  onPressed: () =>
                      context.push('/catalog/item/${widget.itemId}/timeline'),
                  child: const Text('Full timeline'),
                ),
              ],
            ),
            if (warehouse.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Warehouse: $warehouse',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: HexaColors.neutral,
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Search movements…',
                prefixIcon: Icon(Icons.search_rounded, size: 18),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in _TimelineKindFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(switch (f) {
                          _TimelineKindFilter.all => 'All',
                          _TimelineKindFilter.purchase => 'Purchases',
                          _TimelineKindFilter.adjustment => 'Adjustments',
                          _TimelineKindFilter.transfer => 'Transfers',
                          _TimelineKindFilter.sale => 'Sales',
                          _TimelineKindFilter.physical => 'Physical',
                        }),
                        selected: _kind == f,
                        onSelected: (_) => setState(() {
                          _kind = f;
                          _visibleLimit = 12;
                        }),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => FriendlyLoadError(
                message: 'Could not load timeline',
                onRetry: () =>
                    ref.invalidate(stockItemActivityProvider(widget.itemId)),
              ),
              data: (m) {
                final raw = (m['activity'] as List?) ?? const [];
                final allRows = raw
                    .whereType<Map>()
                    .map((e) => Map<dynamic, dynamic>.from(e))
                    .where(_matchesKind)
                    .where((r) => _matchesSearch(r, q))
                    .toList();
                if (allRows.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 20, 8, 20),
                    child: Column(
                      children: [
                        Icon(
                          Icons.timeline_outlined,
                          size: 40,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'No activity yet',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          q.isNotEmpty || _kind != _TimelineKindFilter.all
                              ? 'No movements match these filters'
                              : 'Purchases, adjustments, and stock moves will show here',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final rows = allRows.take(_visibleLimit).toList();
                final df = DateFormat('dd MMM • h:mm a');
                return Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      _TimelineRow(
                        title: (rows[i]['title']?.toString().trim().isNotEmpty ==
                                true)
                            ? rows[i]['title'].toString().trim()
                            : _fallbackTitle(rows[i]),
                        who: rows[i]['actor_name']?.toString(),
                        when: () {
                          final atRaw = rows[i]['created_at']?.toString() ??
                              rows[i]['occurred_at']?.toString();
                          final at = atRaw != null
                              ? DateTime.tryParse(atRaw)?.toLocal()
                              : null;
                          return at != null ? df.format(at) : '—';
                        }(),
                        kind: rows[i]['kind']?.toString(),
                      ),
                      if (i < rows.length - 1) const Divider(height: 12),
                    ],
                    if (allRows.length > _visibleLimit) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => setState(() => _visibleLimit += 12),
                        child: Text(
                          'Load more (${allRows.length - _visibleLimit} left)',
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _fallbackTitle(Map row) {
    final kind = row['kind']?.toString().trim() ?? '';
    if (kind.isEmpty) return 'Stock movement';
    return kind.replaceAll('_', ' ');
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.title,
    required this.who,
    required this.when,
    this.kind,
  });
  final String title;
  final String? who;
  final String when;
  final String? kind;

  @override
  Widget build(BuildContext context) {
    final whoT = who?.trim() ?? '';
    final kindT = kind?.trim() ?? '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.circle, size: 10, color: HexaColors.cost),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  when,
                  if (whoT.isNotEmpty) whoT,
                  if (kindT.isNotEmpty) kindT.replaceAll('_', ' '),
                ].join(' • '),
                style: const TextStyle(
                  fontSize: 11,
                  color: HexaColors.neutral,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
