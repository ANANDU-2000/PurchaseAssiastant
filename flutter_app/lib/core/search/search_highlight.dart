import 'package:flutter/material.dart';

/// Highlights non-overlapping matches of [query] words in [text] (case-insensitive).
List<InlineSpan> highlightSearchQuery(
  String text,
  String query, {
  required TextStyle baseStyle,
  required TextStyle highlightStyle,
}) {
  if (text.isEmpty) return [TextSpan(text: '', style: baseStyle)];
  final raw = query.trim();
  if (raw.isEmpty) return [TextSpan(text: text, style: baseStyle)];

  final words = raw
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty)
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));

  if (words.isEmpty) return [TextSpan(text: text, style: baseStyle)];

  final pattern = words.map(RegExp.escape).join('|');
  final re = RegExp(pattern, caseSensitive: false);
  final spans = <InlineSpan>[];
  var start = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > start) {
      spans.add(TextSpan(text: text.substring(start, m.start), style: baseStyle));
    }
    spans.add(TextSpan(text: text.substring(m.start, m.end), style: highlightStyle));
    start = m.end;
  }
  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start), style: baseStyle));
  }
  return spans;
}
