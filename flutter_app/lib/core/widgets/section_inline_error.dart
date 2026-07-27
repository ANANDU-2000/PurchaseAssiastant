import 'package:flutter/material.dart';

import '../design_system/hexa_inline_button.dart';

/// Compact inline error for narrow cards — avoids [ListTile] squeezing title to 1 char/line.
class SectionInlineError extends StatelessWidget {
  const SectionInlineError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        HexaInlineButton.fullWidth(
          context: context,
          label: 'Retry',
          onPressed: onRetry,
          filled: false,
        ),
      ],
    );
  }
}
