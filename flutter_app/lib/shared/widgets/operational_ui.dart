import 'package:flutter/material.dart';

import '../../core/design_system/hexa_ds_tokens.dart';
import '../../core/theme/hexa_colors.dart';

/// Grouped section shell — dense operational panel (not floating SaaS card).
class OperationalSection extends StatelessWidget {
  const OperationalSection({
    super.key,
    required this.title,
    this.trailing,
    required this.child,
    this.dense = true,
  });

  final String title;
  final Widget? trailing;
  final Widget child;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HexaColors.brandBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(12, dense ? 8 : 10, 12, dense ? 4 : 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: HexaDsType.heading(14, color: HexaDsColors.textPrimary),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Horizontal scroll filter pills (category / supplier / status).
class OperationalPillRow extends StatelessWidget {
  const OperationalPillRow({
    super.key,
    required this.labels,
    this.selected,
    required this.onSelected,
    this.height = 34,
  });

  final List<String> labels;
  final String? selected;
  final ValueChanged<String> onSelected;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final label = labels[i];
          final on = selected == label;
          return FilterChip(
            label: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: on ? Colors.white : HexaDsColors.textPrimary,
              ),
            ),
            selected: on,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            selectedColor: HexaColors.brandPrimary,
            backgroundColor: const Color(0xFFF1F5F9),
            side: BorderSide(
              color: on ? HexaColors.brandPrimary : HexaColors.brandBorder,
            ),
            onSelected: (_) => onSelected(label),
          );
        },
      ),
    );
  }
}

/// Circular quick action — thumb-friendly, compact.
class CircularQuickAction extends StatelessWidget {
  const CircularQuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? HexaColors.brandPrimary;
    return SizedBox(
      width: 64,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: c.withValues(alpha: 0.35)),
              ),
              child: Icon(icon, color: c, size: 22),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact inline stat chip (not giant KPI card).
class OperationalStatChip extends StatelessWidget {
  const OperationalStatChip({
    super.key,
    required this.label,
    required this.value,
    this.tint,
    this.onTap,
  });

  final String label;
  final String value;
  final Color? tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = tint ?? HexaColors.brandPrimary;
    return Material(
      color: bg.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: bg.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: bg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Date section header for ledger-style lists.
class OperationalDateHeader extends StatelessWidget {
  const OperationalDateHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFE8EDF3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
          color: Color(0xFF475569),
        ),
      ),
    );
  }
}
