import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/widgets/friendly_load_error.dart';

/// Server-backed unified search (items, suppliers).
final unifiedSearchProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, q) async {
    final session = ref.watch(sessionProvider);
    if (session == null || q.trim().isEmpty) {
      return {
        'catalog_items': <dynamic>[],
        'suppliers': <dynamic>[],
      };
    }
    return ref.read(hexaApiProvider).unifiedSearch(
          businessId: session.primaryBusiness.id,
          q: q.trim(),
        );
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
  String _section = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sec = GoRouterState.of(context).uri.queryParameters['section'];
      if (sec == 'all' || sec == 'items' || sec == 'suppliers') {
        setState(() => _section = sec!);
      }
      _focus.requestFocus();
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
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final next = v.trim();
      if (next == _debounced) return;
      setState(() => _debounced = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final q = _debounced.toLowerCase();
    final searchAsync = q.isNotEmpty
        ? ref.watch(unifiedSearchProvider(_debounced))
        : const AsyncValue<Map<String, dynamic>>.data({});

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
            hintText: 'Name, HSN, category, supplier, GST…',
            textInputAction: TextInputAction.search,
            textStyle: const WidgetStatePropertyAll(TextStyle()),
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
          if (q.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                'Type one letter to search items (name, HSN, category) and suppliers.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            )
          else
            searchAsync.when(
              skipLoadingOnReload: true,
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => FriendlyLoadError(
                message: 'Search failed',
                onRetry: () => ref.invalidate(unifiedSearchProvider(q)),
              ),
              data: (data) {
                final items = (data['catalog_items'] as List<dynamic>?)
                        ?.map((e) => Map<String, dynamic>.from(e as Map))
                        .toList() ??
                    [];
                final suppliers = (data['suppliers'] as List<dynamic>?)
                        ?.map((e) => Map<String, dynamic>.from(e as Map))
                        .toList() ??
                    [];
                final sectionCounts = <String, int>{
                  'items': items.length,
                  'suppliers': suppliers.length,
                };
                final hasAnyResult = items.isNotEmpty || suppliers.isNotEmpty;
                final fuzzyItems =
                    data['fuzzy_catalog_used'] == true;
                final fuzzySup =
                    data['fuzzy_suppliers_used'] == true;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (fuzzyItems || fuzzySup)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          fuzzyItems && fuzzySup
                              ? 'No exact title match — showing close catalog and supplier matches.'
                              : fuzzyItems
                                  ? 'No exact item title match — showing close matches (typos OK).'
                                  : 'No exact supplier name match — showing close matches.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ),
                    if (hasAnyResult) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('All'),
                            selected: _section == 'all',
                            onSelected: (_) => setState(() => _section = 'all'),
                          ),
                          ChoiceChip(
                            label: Text('Items (${sectionCounts['items']})'),
                            selected: _section == 'items',
                            onSelected: (_) =>
                                setState(() => _section = 'items'),
                          ),
                          ChoiceChip(
                            label:
                                Text('Suppliers (${sectionCounts['suppliers']})'),
                            selected: _section == 'suppliers',
                            onSelected: (_) =>
                                setState(() => _section = 'suppliers'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_section == 'all' || _section == 'items') ...[
                    Text(
                      'Items',
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (items.isEmpty)
                      Text(
                        'No matching catalog items.',
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      )
                    else
                      ...items.map((m) {
                        final id = m['id']?.toString() ?? '';
                        final name = m['name']?.toString() ?? 'Item';
                        final cat = m['category_name']?.toString();
                        final typ = m['type_name']?.toString();
                        final sub = [cat, typ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.inventory_2_outlined,
                              color: cs.primary),
                          title: Text(name),
                          subtitle: sub.isEmpty
                              ? null
                              : Text(
                                  sub,
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                          trailing:
                              const Icon(Icons.chevron_right_rounded),
                          onTap: id.isEmpty
                              ? null
                              : () => context.push('/catalog/item/$id'),
                        );
                      }),
                    const SizedBox(height: 24),
                    ],
                    if (_section == 'all' || _section == 'suppliers') ...[
                    Text(
                      'Suppliers',
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (suppliers.isEmpty)
                      Text(
                        'No matching suppliers.',
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      )
                    else
                      ...suppliers.map((m) {
                        final id = m['id']?.toString() ?? '';
                        final name = m['name']?.toString() ?? 'Supplier';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.storefront_outlined,
                              color: cs.primary),
                          title: Text(name),
                          trailing:
                              const Icon(Icons.chevron_right_rounded),
                          onTap: id.isEmpty
                              ? null
                              : () => context.push('/supplier/$id'),
                        );
                      }),
                    const SizedBox(height: 24),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
