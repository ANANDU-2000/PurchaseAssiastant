import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/suppliers_list_provider.dart';

/// Server-backed entry search (does not mutate [entrySearchQueryProvider]).
final globalSearchEntriesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, q) async {
    final session = ref.watch(sessionProvider);
    if (session == null || q.trim().length < 2) return [];
    final raw = await ref.read(hexaApiProvider).listEntries(
          businessId: session.primaryBusiness.id,
          item: q.trim(),
        );
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  },
);

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _debounced = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scheduleSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _debounced = v.trim());
    });
  }

  static String _entryTitle(Map<String, dynamic> e) {
    final lines = e['lines'];
    if (lines is! List || lines.isEmpty) return 'Purchase entry';
    final first = lines.first;
    if (first is! Map) return 'Purchase entry';
    final name = first['item_name'] as String? ?? 'Item';
    if (lines.length == 1) return name;
    return '$name +${lines.length - 1} more';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final q = _debounced.toLowerCase();
    final itemsAsync = ref.watch(catalogItemsListProvider);
    final supAsync = ref.watch(suppliersListProvider);
    final entriesAsync = q.length >= 2
        ? ref.watch(globalSearchEntriesProvider(_debounced))
        : const AsyncValue<List<Map<String, dynamic>>>.data([]);

    List<Map<String, dynamic>> filterItems(
        List<Map<String, dynamic>> all, String needle) {
      if (needle.length < 2) return [];
      return all
          .where((m) =>
              (m['name']?.toString() ?? '').toLowerCase().contains(needle))
          .take(5)
          .toList();
    }

    List<Map<String, dynamic>> filterSuppliers(
        List<Map<String, dynamic>> all, String needle) {
      if (needle.length < 2) return [];
      return all
          .where((m) =>
              (m['name']?.toString() ?? '').toLowerCase().contains(needle))
          .take(5)
          .toList();
    }

    final itemRows = itemsAsync.maybeWhen(
      data: (list) => filterItems(list, q),
      orElse: () => <Map<String, dynamic>>[],
    );
    final supRows = supAsync.maybeWhen(
      data: (list) => filterSuppliers(list, q),
      orElse: () => <Map<String, dynamic>>[],
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Search'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          SearchBar(
            focusNode: _focus,
            controller: _controller,
            hintText: 'Search items, suppliers, entries…',
            leading: const Icon(Icons.search_rounded),
            trailing: [
              if (_controller.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _controller.clear();
                    setState(() => _debounced = '');
                    _scheduleSearch('');
                  },
                ),
            ],
            onChanged: (v) {
              setState(() {});
              _scheduleSearch(v);
            },
          ),
          const SizedBox(height: 16),
          if (q.length < 2)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                'Type at least 2 characters to search.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            Text(
              'Items',
              style: tt.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            if (itemRows.isEmpty)
              Text(
                'No matching catalog items.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              )
            else
              ...itemRows.map((m) {
                final id = m['id']?.toString() ?? '';
                final name = m['name']?.toString() ?? 'Item';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.inventory_2_outlined, color: cs.primary),
                  title: Text(name),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: id.isEmpty
                      ? null
                      : () => context.push('/catalog/item/$id'),
                );
              }),
            const SizedBox(height: 24),
            Text(
              'Suppliers',
              style: tt.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            if (supRows.isEmpty)
              Text(
                'No matching suppliers.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              )
            else
              ...supRows.map((m) {
                final id = m['id']?.toString() ?? '';
                final name = m['name']?.toString() ?? 'Supplier';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.storefront_outlined, color: cs.primary),
                  title: Text(name),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: id.isEmpty
                      ? null
                      : () => context.push('/supplier/$id'),
                );
              }),
            const SizedBox(height: 24),
            Text(
              'Entries',
              style: tt.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            entriesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => Text(
                'Could not search entries.',
                style: tt.bodySmall?.copyWith(color: cs.error),
              ),
              data: (entries) {
                final five = entries.take(5).toList();
                if (five.isEmpty) {
                  return Text(
                    'No matching purchase entries.',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  );
                }
                return Column(
                  children: five.map((e) {
                    final id = e['id']?.toString() ?? '';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.receipt_long_rounded,
                          color: cs.primary),
                      title: Text(_entryTitle(e)),
                      subtitle: Text(
                        e['entry_date']?.toString().split('T').first ?? '',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: id.isEmpty
                          ? null
                          : () => context.push('/entry/$id'),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
