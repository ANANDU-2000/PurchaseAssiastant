import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';

/// Server-backed unified search (items, suppliers, entries).
final unifiedSearchProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, q) async {
    final session = ref.watch(sessionProvider);
    if (session == null || q.trim().length < 2) {
      return {
        'catalog_items': <dynamic>[],
        'suppliers': <dynamic>[],
        'entries': <dynamic>[],
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
    final searchAsync = q.length >= 2
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
          else
            searchAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  'Search failed. Try again.',
                  style: tt.bodySmall?.copyWith(color: cs.error),
                ),
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
                final entries = (data['entries'] as List<dynamic>?)
                        ?.map((e) => Map<String, dynamic>.from(e as Map))
                        .toList() ??
                    [];

                final suggestDidYouMean = items.isEmpty &&
                    entries.isNotEmpty &&
                    q.length >= 3;
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
                    if (suggestDidYouMean)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'No catalog item title matched — showing entries that mention your text. '
                          'Add the item under Catalog if you want it as a master row.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ),
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
                    Text(
                      'Entries',
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (entries.isEmpty)
                      Text(
                        'No matching purchase entries.',
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      )
                    else
                      ...entries.take(12).map((e) {
                        final id = e['id']?.toString() ?? '';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.receipt_long_rounded,
                              color: cs.primary),
                          title: Text(_entryTitle(e)),
                          subtitle: Text(
                            e['entry_date']?.toString().split('T').first ??
                                '',
                          ),
                          trailing:
                              const Icon(Icons.chevron_right_rounded),
                          onTap: id.isEmpty
                              ? null
                              : () => context.push('/entry/$id'),
                        );
                      }),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
