import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reserved for future scoped write fan-out.
///
/// Purchase/stock invalidation is handled at call sites
/// ([invalidatePurchaseWorkspace], [invalidateWarehouseSurfaces], etc.).
/// A shell listener that re-invalidated on every write caused refresh storms
/// and broken tabs after staff updates.
class BusinessWriteStockListener extends ConsumerWidget {
  const BusinessWriteStockListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return child;
  }
}
