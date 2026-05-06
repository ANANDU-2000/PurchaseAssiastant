import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_error_messages.dart';

/// Confirms destructive or high-impact actions (delete, remove row, etc.).
Future<bool> confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String message,
  String cancelLabel = 'Cancel',
  String confirmLabel = 'Delete',
  Color? confirmButtonColor,
}) async {
  final cs = Theme.of(context).colorScheme;
  final bg = confirmButtonColor ?? cs.error;
  final fg = confirmButtonColor != null ? cs.onSurface : cs.onError;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => ctx.pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
          ),
          onPressed: () => ctx.pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// User-visible failure with an explicit retry (network, timeouts, 5xx).
void showRetryableErrorSnackBar(
  BuildContext context,
  Object error, {
  required VoidCallback onRetry,
  String? message,
}) {
  if (!context.mounted) return;
  final text = message ?? friendlyApiError(error);
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text),
      action: SnackBarAction(
        label: 'Retry',
        onPressed: onRetry,
      ),
    ),
  );
}
