import 'package:flutter/material.dart';

import '../../core/theme/hexa_colors.dart';

/// Full-screen date range picker (avoids keyboard/sheet overlap on history filters).
Future<DateTimeRange?> showFullscreenDateRangePicker(
  BuildContext context, {
  required DateTime initialStart,
  required DateTime initialEnd,
  DateTime? firstDate,
  DateTime? lastDate,
  String title = 'Select date range',
}) async {
  final now = DateTime.now();
  final first = firstDate ?? DateTime(now.year - 5, 1, 1);
  final last = lastDate ?? DateTime(now.year + 1, 12, 31);
  var start = DateTime(initialStart.year, initialStart.month, initialStart.day);
  var end = DateTime(initialEnd.year, initialEnd.month, initialEnd.day);
  if (start.isAfter(end)) {
    final t = start;
    start = end;
    end = t;
  }

  return Navigator.of(context).push<DateTimeRange>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) {
        return _FullscreenDateRangePage(
          title: title,
          first: first,
          last: last,
          initialStart: start,
          initialEnd: end,
        );
      },
    ),
  );
}

class _FullscreenDateRangePage extends StatefulWidget {
  const _FullscreenDateRangePage({
    required this.title,
    required this.first,
    required this.last,
    required this.initialStart,
    required this.initialEnd,
  });

  final String title;
  final DateTime first;
  final DateTime last;
  final DateTime initialStart;
  final DateTime initialEnd;

  @override
  State<_FullscreenDateRangePage> createState() =>
      _FullscreenDateRangePageState();
}

class _FullscreenDateRangePageState extends State<_FullscreenDateRangePage> {
  late DateTime _start;
  late DateTime _end;
  bool _pickingEnd = false;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(
                context,
                DateTimeRange(start: _start, end: _end),
              );
            },
            child: const Text('Apply'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _DateChip(
                      label: 'From',
                      date: _start,
                      selected: !_pickingEnd,
                      onTap: () => setState(() => _pickingEnd = false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateChip(
                      label: 'To',
                      date: _end,
                      selected: _pickingEnd,
                      onTap: () => setState(() => _pickingEnd = true),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: CalendarDatePicker(
                initialDate: _pickingEnd ? _end : _start,
                firstDate: widget.first,
                lastDate: widget.last,
                onDateChanged: (d) {
                  setState(() {
                    final day = DateTime(d.year, d.month, d.day);
                    if (_pickingEnd) {
                      _end = day;
                      if (_end.isBefore(_start)) _start = _end;
                    } else {
                      _start = day;
                      if (_start.isAfter(_end)) _end = _start;
                    }
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: HexaColors.brandPrimary,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () {
                  Navigator.pop(
                    context,
                    DateTimeRange(start: _start, end: _end),
                  );
                },
                child: const Text('Apply range'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.date,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final df = '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
    return Material(
      color: selected
          ? HexaColors.brandPrimary.withValues(alpha: 0.12)
          : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? HexaColors.brandPrimary
                      : Colors.grey.shade600,
                ),
              ),
              Text(
                df,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? HexaColors.brandPrimary
                      : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
