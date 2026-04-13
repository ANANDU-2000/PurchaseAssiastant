import 'package:flutter/material.dart';

import '../theme/hexa_colors.dart';

/// Default [FriendlyLoadError.subtitle] for typical network / connectivity failures.
const String kFriendlyLoadNetworkSubtitle =
    'Check your connection and try again.';

/// Inline error state with retry — avoids exposing raw exception strings to users.
class FriendlyLoadError extends StatelessWidget {
  const FriendlyLoadError({
    super.key,
    required this.onRetry,
    this.message = 'Could not load data',
    this.subtitle = kFriendlyLoadNetworkSubtitle,
  });

  final VoidCallback onRetry;
  final String message;

  /// Shown under [message]. Defaults to [kFriendlyLoadNetworkSubtitle]; pass `null` to hide.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 40,
                color: HexaColors.textSecondary.withValues(alpha: 0.9)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: tt.bodyLarge?.copyWith(
                  color: HexaColors.textPrimary, fontWeight: FontWeight.w600),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: tt.bodySmall
                    ?.copyWith(color: HexaColors.textSecondary, height: 1.35),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
