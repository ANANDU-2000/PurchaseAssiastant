import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';

class UserActivityTimeline extends StatelessWidget {
  const UserActivityTimeline({
    super.key,
    required this.rows,
    this.emptyMessage = 'No activity in the last 30 days.',
  });

  final List<Map<String, dynamic>> rows;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyMessage, style: HexaDsType.bodyPrimary(context)),
        ),
      );
    }

    final grouped = _groupByDay(rows);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text(entry.key, style: HexaDsType.h3(context)),
          ),
          for (final row in entry.value)
            _TimelineRow(row: row),
        ],
      ],
    );
  }

  Map<String, List<Map<String, dynamic>>> _groupByDay(
    List<Map<String, dynamic>> rows,
  ) {
    final sorted = [...rows]..sort((a, b) {
        final da = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final db = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });

    final out = <String, List<Map<String, dynamic>>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final row in sorted) {
      final at = DateTime.tryParse(row['created_at']?.toString() ?? '');
      final label = _dayLabel(at, today);
      out.putIfAbsent(label, () => []).add(row);
    }
    return out;
  }

  static String _dayLabel(DateTime? at, DateTime today) {
    if (at == null) return 'Earlier';
    final local = at.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    if (today.difference(day).inDays < 7) {
      return DateFormat('EEEE').format(local);
    }
    return DateFormat.yMMMd().format(local);
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final at = DateTime.tryParse(row['created_at']?.toString() ?? '');
    final time = at != null ? DateFormat.jm().format(at.toLocal()) : '';
    final title = _friendlyAction(row['action_type']?.toString() ?? '');
    final item = row['item_name']?.toString();

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6, right: 10),
            decoration: BoxDecoration(
              color: HexaColors.brandPrimary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: HexaDsType.bodyPrimary(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item != null && item.isNotEmpty)
                  Text(item, style: HexaDsType.bodySm(context)),
                if (time.isNotEmpty)
                  Text(time, style: HexaDsType.bodySm(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _friendlyAction(String raw) {
    return raw
        .replaceAll('_', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
