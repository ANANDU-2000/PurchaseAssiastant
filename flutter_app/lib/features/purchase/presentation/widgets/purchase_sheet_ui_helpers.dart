import 'package:flutter/material.dart';

class SheetWarningPill extends StatelessWidget {
  const SheetWarningPill({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFEDD5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFF9A3412)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9A3412),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SheetSummaryPill extends StatelessWidget {
  const SheetSummaryPill({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    required this.color,
  });
  final String label;
  final String value;
  final String? subtitle;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: color.withValues(alpha: 0.7))),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A))),
        if (subtitle != null)
          Text(subtitle!,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

class SheetMetric extends StatelessWidget {
  const SheetMetric({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.isBold = false,
  });
  final String label;
  final String value;
  final Color color;
  final bool isBold;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: const Color(0xFF64748B).withValues(alpha: 0.7))),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 14,
                fontWeight: isBold ? FontWeight.w900 : FontWeight.w800,
                color: color)),
      ],
    );
  }
}
