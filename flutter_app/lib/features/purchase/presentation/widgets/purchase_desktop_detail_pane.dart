import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/models/trade_purchase_models.dart';
import '../../../../core/router/post_auth_route.dart' show sessionCanSeeFinancials;
import '../../../../core/widgets/friendly_load_error.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../providers/trade_purchase_detail_provider.dart'
    show
        tradePurchaseDetailProvider,
        tradePurchaseDeliveryOptimisticProvider;
import '../purchase_detail_page.dart';

/// Desktop purchase history right pane — embeds [PurchaseDetailBody].
class PurchaseDesktopDetailPane extends ConsumerWidget {
  const PurchaseDesktopDetailPane({
    super.key,
    required this.purchaseId,
    this.seedPurchase,
  });

  final String? purchaseId;
  final TradePurchase? seedPurchase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (purchaseId == null || purchaseId!.isEmpty) {
      return const ColoredBox(
        color: Color(0xFFFAFAF8),
        child: Center(
          child: Text(
            'Select a purchase',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
        ),
      );
    }
    final async = ref.watch(tradePurchaseDetailProvider(purchaseId!));
    final seedOk =
        seedPurchase != null && seedPurchase!.id == purchaseId;
    final session = ref.watch(sessionProvider);
    final hideFinancials =
        session != null && !sessionCanSeeFinancials(session);
    final optim = ref.watch(
      tradePurchaseDeliveryOptimisticProvider(purchaseId!),
    );

    return ColoredBox(
      color: const Color(0xFFFAFAF8),
      child: async.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () {
          if (seedOk) {
            final p = optim == null
                ? seedPurchase!
                : seedPurchase!.withDelivered(optim);
            return PurchaseDetailBody(
              p: p,
              hideFinancials: hideFinancials,
              embedded: true,
            );
          }
          return const Center(child: ListSkeleton());
        },
        error: (e, _) => FriendlyLoadError(
          message: 'Could not load purchase',
          onRetry: () =>
              ref.invalidate(tradePurchaseDetailProvider(purchaseId!)),
        ),
        data: (p) {
          final displayP = optim == null ? p : p.withDelivered(optim);
          return PurchaseDetailBody(
            p: displayP,
            hideFinancials: hideFinancials,
            embedded: true,
          );
        },
      ),
    );
  }
}
