import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../shared/widgets/hexa_empty_state.dart';

final catalogDuplicatesProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return <String, dynamic>{};
  return ref.read(hexaApiProvider).getCatalogDuplicateClusters(
        businessId: session.primaryBusiness.id,
      );
});

class CatalogDuplicatesPage extends ConsumerWidget {
  const CatalogDuplicatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(catalogDuplicatesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Possible duplicates'),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => CatalogDuplicatesLoadError(
          onRetry: () => ref.invalidate(catalogDuplicatesProvider),
        ),
        data: (m) {
          final pairs = [
            for (final p in (m['pairs'] as List? ?? []))
              if (p is Map) Map<String, dynamic>.from(p),
          ];
          if (pairs.isEmpty) {
            return HexaEmptyState(
              icon: Icons.verified_outlined,
              title: 'No similar names found',
              subtitle: 'Catalog hygiene looks good — no near-duplicate pairs.',
              primaryActionLabel: 'Open catalog',
              onPrimaryAction: () => context.go('/catalog'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: pairs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final p = pairs[i];
              final score = ((p['score'] as num?) ?? 0) * 100;
              return ListTile(
                title: Text(
                  '${p['name_a']} ↔ ${p['name_b']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${score.toStringAsFixed(0)}% similar'),
                trailing: TextButton(
                  onPressed: () async {
                    final id = p['id_b']?.toString();
                    if (id == null) return;
                    final session = ref.read(sessionProvider);
                    if (session == null) return;
                    try {
                      await ref.read(hexaApiProvider).bulkArchiveCatalogItems(
                            businessId: session.primaryBusiness.id,
                            itemIds: [id],
                          );
                      ref.invalidate(catalogDuplicatesProvider);
                      ref.invalidate(catalogItemsListProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Archived duplicate')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(userFacingError(e)),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Archive B'),
                ),
                onTap: () {
                  final id = p['id_a']?.toString();
                  if (id != null && id.isNotEmpty) {
                    context.push('/catalog/item/$id');
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Catalog duplicates clusters load failure (UX-138).
@visibleForTesting
class CatalogDuplicatesLoadError extends StatelessWidget {
  const CatalogDuplicatesLoadError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return HexaEmptyState(
      icon: Icons.content_copy_outlined,
      title: 'Could not load duplicate suggestions',
      subtitle: 'Check your connection, then retry.',
      primaryActionLabel: 'Retry',
      onPrimaryAction: onRetry,
    );
  }
}
