import 'package:flutter/material.dart';

/// Consistent page header for all major pages.
///
/// Layout:
/// ```
/// Title                          Primary action
/// Optional description
/// ```
///
/// Height: ~64px when description present, ~48px without.
/// This widget is NOT inside scrollable content — it sits above the content area.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.description,
    this.primaryAction,
    this.secondaryActions = const [],
  });

  final String title;
  final String? description;
  final Widget? primaryAction;
  final List<Widget> secondaryActions;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          // ── Title + description ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: tt.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // ── Secondary actions ──
          for (final action in secondaryActions) ...[
            const SizedBox(width: 4),
            action,
          ],
          // ── Primary action ──
          if (primaryAction != null) ...[
            const SizedBox(width: 8),
            primaryAction!,
          ],
        ],
      ),
    );
  }
}
