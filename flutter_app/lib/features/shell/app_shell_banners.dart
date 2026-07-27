import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/hexa_ds_tokens.dart';
import '../../core/providers/connectivity_provider.dart';
import '../../core/services/offline_store.dart';

/// Shared offline / pending-sync banners for owner and staff shells.
class AppShellConnectivityBanners extends ConsumerWidget {
  const AppShellConnectivityBanners({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectivityResultsProvider);
    final offline =
        conn.valueOrNull != null && isOfflineResult(conn.valueOrNull!);
    final pendingSync = OfflineStore.getPendingEntries().length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (offline)
          Semantics(
            liveRegion: true,
            container: true,
            label: "You're offline — showing cached data",
            child: Material(
              color: const Color(0xFFF59E0B),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: HexaDsLayout.pageGutter,
                  vertical: HexaDsSpace.xs + 2,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off_rounded,
                        size: 18, color: Color(0xFF1C1917)),
                    const SizedBox(width: HexaDsLayout.inlineGap),
                    Expanded(
                      child: Text(
                        "You're offline — showing cached data",
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: const Color(0xFF1C1917),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  height: 1.25,
                                ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (!offline && pendingSync > 0)
          Material(
            color: const Color(0xFFE3F2FD),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: HexaDsLayout.pageGutter,
                vertical: HexaDsSpace.xs + 2,
              ),
              child: Row(
                children: [
                  const Icon(Icons.sync, size: 18, color: Color(0xFF1565C0)),
                  const SizedBox(width: HexaDsLayout.inlineGap),
                  Expanded(
                    child: Text(
                      pendingSync == 1
                          ? '1 change pending sync'
                          : '$pendingSync changes pending sync',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: const Color(0xFF1565C0),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            height: 1.25,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
