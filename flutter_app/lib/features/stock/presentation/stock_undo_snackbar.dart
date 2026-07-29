import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';

/// One-shot undo after a quick stock patch (server validates 15 min / same user).
void showStockUndoSnackBar({
  BuildContext? context,
  ScaffoldMessengerState? messenger,
  required WidgetRef ref,
  required String itemId,
  required String itemName,
}) {
  final m = messenger ??
      (context != null ? ScaffoldMessenger.maybeOf(context) : null);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text('Stock updated — $itemName'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          final session = ref.read(sessionProvider);
          if (session == null) return;
          try {
            await ref.read(hexaApiProvider).undoLastStockChange(
                  businessId: session.primaryBusiness.id,
                  itemId: itemId,
                );
            invalidateStockRowSaveSurfaces(
              ref,
              itemId: itemId,
              immediateListReconcile: true,
              refreshItemDetail: true,
            );
            m.showSnackBar(
              const SnackBar(content: Text('Change undone')),
            );
          } catch (_) {
            m.showSnackBar(
              const SnackBar(
                content: Text('Could not undo — change may be too old'),
              ),
            );
          }
        },
      ),
      duration: const Duration(seconds: 12),
    ),
  );
}
