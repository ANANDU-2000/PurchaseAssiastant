import 'package:flutter/material.dart';

/// Centered empty state — neutral chrome, optional primary CTA (always guide next step).
class HexaEmptyState extends StatelessWidget {
  const HexaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.primaryActionLabel,
    this.onPrimaryAction,
  }) : assert(
          (primaryActionLabel == null && onPrimaryAction == null) ||
              (primaryActionLabel != null && onPrimaryAction != null),
          'Provide both primaryActionLabel and onPrimaryAction, or neither.',
        );

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Custom trailing widget (e.g. row of buttons). Shown below subtitle.
  final Widget? action;

  /// Shorthand for a single [FilledButton] — prefer this over bare [action] when possible.
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.surfaceContainerHighest.withValues(alpha: 0.9),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.85),
                ),
              ),
              child: Icon(icon, size: 40, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (primaryActionLabel != null && onPrimaryAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onPrimaryAction,
                child: Text(primaryActionLabel!),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
