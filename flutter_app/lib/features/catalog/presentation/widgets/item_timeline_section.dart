import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/providers/stock_providers.dart';
import '../../../../core/widgets/friendly_load_error.dart';

class ItemTimelineSection extends ConsumerWidget {
  const ItemTimelineSection({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(stockItemActivityProvider(itemId));
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(HexaOp.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Timeline', style: HexaOp.cardTitle(context)),
            const SizedBox(height: 8),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => FriendlyLoadError(
                message: 'Could not load timeline',
                onRetry: () => ref.invalidate(stockItemActivityProvider(itemId)),
              ),
              data: (m) {
                final raw = (m['activity'] as List?) ?? const [];
                final rows = raw.whereType<Map>().take(8).toList();
                if (rows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(12, 14, 12, 14),
                    child: Text(
                      'No recent events.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  );
                }
                final df = DateFormat('dd MMM • h:mm a');
                return Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      _TimelineRow(
                        title: rows[i]['title']?.toString() ?? 'Event',
                        who: rows[i]['actor_name']?.toString(),
                        when: () {
                          final atRaw = rows[i]['created_at']?.toString();
                          final at = atRaw != null
                              ? DateTime.tryParse(atRaw)?.toLocal()
                              : null;
                          return at != null ? df.format(at) : '—';
                        }(),
                      ),
                      if (i < rows.length - 1)
                        const Divider(height: 12),
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
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.title, required this.who, required this.when});
  final String title;
  final String? who;
  final String when;

  @override
  Widget build(BuildContext context) {
    final whoT = who?.trim() ?? '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.circle, size: 10, color: Color(0xFF94A3B8)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
              const SizedBox(height: 2),
              Text(
                [when, if (whoT.isNotEmpty) whoT].join(' • '),
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

