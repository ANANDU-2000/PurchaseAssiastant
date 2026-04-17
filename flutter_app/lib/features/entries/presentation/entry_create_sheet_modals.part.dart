part of 'entry_create_sheet.dart';

/// Category chips → item list → variant/type when multiple (cash-register flow).
class _CatalogItemPickModal extends StatefulWidget {
  const _CatalogItemPickModal({
    required this.categories,
    required this.items,
    required this.categoryNames,
    required this.recentLines,
    required this.topLines,
    required this.loadVariants,
    required this.onPick,
  });

  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> items;
  final Map<String, String> categoryNames;
  final List<Map<String, dynamic>> recentLines;
  final List<Map<String, dynamic>> topLines;
  final Future<List<Map<String, dynamic>>> Function(String itemId)
      loadVariants;
  final void Function(
    Map<String, dynamic> item, {
    String? catalogVariantId,
    Map<String, dynamic>? variant,
  }) onPick;

  @override
  State<_CatalogItemPickModal> createState() => _CatalogItemPickModalState();
}

class _CatalogItemPickModalState extends State<_CatalogItemPickModal> {
  final _search = TextEditingController();
  String? _filterCategoryId;
  bool _variantsLoading = false;
  Map<String, dynamic>? _itemForVariantStep;
  List<Map<String, dynamic>>? _variantsForItem;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _selectCatalogItem(Map<String, dynamic> it) async {
    final id = it['id']?.toString();
    if (id == null || id.isEmpty) {
      widget.onPick(it);
      return;
    }
    setState(() => _variantsLoading = true);
    try {
      final vars = await widget.loadVariants(id);
      if (!mounted) return;
      if (vars.isEmpty) {
        widget.onPick(it);
        return;
      }
      if (vars.length == 1) {
        final v = vars.first;
        widget.onPick(
          it,
          catalogVariantId: v['id']?.toString(),
          variant: v,
        );
        return;
      }
      setState(() {
        _variantsLoading = false;
        _itemForVariantStep = it;
        _variantsForItem = vars;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _variantsLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load types for this item')),
      );
    }
  }

  void _leaveVariantStep() {
    setState(() {
      _itemForVariantStep = null;
      _variantsForItem = null;
    });
  }

  Map<String, dynamic> _resolveHistoryLine(Map<String, dynamic> line) {
    final id = line['catalog_item_id']?.toString();
    if (id != null && id.isNotEmpty) {
      for (final it in widget.items) {
        if (it['id']?.toString() == id) return Map<String, dynamic>.from(it);
      }
    }
    final name = line['item_name']?.toString() ?? 'Item';
    final unit = line['unit']?.toString() ?? 'kg';
    return {
      'id': id,
      'name': name,
      'category_id': null,
      'default_unit': unit,
    };
  }

  Widget _historyStrip(
    BuildContext context, {
    required String title,
    required List<Map<String, dynamic>> lines,
  }) {
    if (lines.isEmpty) return const SizedBox.shrink();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(
            title,
            style: tt.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: lines.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final line = lines[i];
              final pick = _resolveHistoryLine(line);
              final label = pick['name']?.toString() ?? '';
              final cid = pick['category_id']?.toString() ?? '';
              final cat = widget.categoryNames[cid] ?? '';
              return Material(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    final vid = line['catalog_variant_id']?.toString();
                    if (vid != null && vid.isNotEmpty) {
                      widget.onPick(pick, catalogVariantId: vid);
                    } else {
                      widget.onPick(pick);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (cat.isNotEmpty)
                          Text(
                            cat,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final variants = _variantsForItem;
    final itemStep = _itemForVariantStep;
    if (itemStep != null && variants != null) {
      final itemName = itemStep['name']?.toString() ?? 'Item';
      final h = MediaQuery.sizeOf(context).height * 0.72;
      final cs = Theme.of(context).colorScheme;
      return SafeArea(
        child: SizedBox(
          height: h,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _leaveVariantStep,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: Text(
                        'Type / variant · $itemName',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 28),
                  itemCount: variants.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final v = variants[i];
                    final id = v['id']?.toString() ?? '';
                    final n = v['name']?.toString() ?? '';
                    final kg = v['default_kg_per_bag'];
                    return ListTile(
                      title: Text(
                        n,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: kg != null
                          ? Text(
                              'Default $kg kg/bag',
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            )
                          : null,
                      onTap: () {
                        widget.onPick(
                          itemStep,
                          catalogVariantId: id.isNotEmpty ? id : null,
                          variant: v,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }

    final q = _search.text.trim().toLowerCase();
    final filtered = widget.items.where((it) {
      final cid = it['category_id']?.toString() ?? '';
      if (_filterCategoryId != null && cid != _filterCategoryId) {
        return false;
      }
      if (q.isEmpty) return true;
      return (it['name']?.toString() ?? '').toLowerCase().contains(q);
    }).toList();

    final h = MediaQuery.sizeOf(context).height * 0.72;
    final showShortcuts = q.isEmpty && _filterCategoryId == null;

    return SafeArea(
      child: SizedBox(
        height: h,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Text(
                'Choose item',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  hintText: 'Search…',
                  prefixIcon: Icon(Icons.search_rounded),
                  filled: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (showShortcuts) ...[
              const SizedBox(height: 8),
              _historyStrip(context,
                  title: 'Recent', lines: widget.recentLines),
              const SizedBox(height: 8),
              _historyStrip(context,
                  title: 'Often used', lines: widget.topLines),
            ],
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: const Text('All'),
                      selected: _filterCategoryId == null,
                      onSelected: (_) =>
                          setState(() => _filterCategoryId = null),
                    ),
                  ),
                  ...widget.categories.map((c) {
                    final id = c['id']?.toString() ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(c['name']?.toString() ?? ''),
                        selected: _filterCategoryId == id,
                        onSelected: (_) => setState(() {
                          _filterCategoryId =
                              _filterCategoryId == id ? null : id;
                        }),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AbsorbPointer(
                      absorbing: _variantsLoading,
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                'No items match — try All or another category',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline,
                                    ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 28),
                              itemCount: filtered.length,
                              itemBuilder: (context, i) {
                                final it = filtered[i];
                                final name = it['name']?.toString() ?? '';
                                final cid = it['category_id']?.toString() ?? '';
                                final du = it['default_unit']?.toString();
                                final sub =
                                    '${widget.categoryNames[cid] ?? ''}${du != null && du.isNotEmpty ? ' · $du' : ''}';
                                return ListTile(
                                  title: Text(
                                    name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(sub),
                                  onTap: () =>
                                      unawaited(_selectCatalogItem(it)),
                                );
                              },
                            ),
                    ),
                  ),
                  if (_variantsLoading)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.white.withValues(alpha: 0.65),
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplierPickerSheet extends StatefulWidget {
  const _SupplierPickerSheet({
    required this.scrollController,
    required this.suppliers,
    required this.selectedId,
    required this.onPick,
  });

  final ScrollController scrollController;
  final List<Map<String, dynamic>> suppliers;
  final String? selectedId;
  final void Function(String?) onPick;

  @override
  State<_SupplierPickerSheet> createState() => _SupplierPickerSheetState();
}

class _SupplierPickerSheetState extends State<_SupplierPickerSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.suppliers
        : widget.suppliers
            .where(
                (s) => (s['name']?.toString() ?? '').toLowerCase().contains(q))
            .toList();
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _search,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Search suppliers',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              ListTile(
                leading: Icon(Icons.layers_clear_rounded,
                    color: widget.selectedId == null
                        ? cs.primary
                        : cs.onSurfaceVariant),
                title: const Text('None'),
                selected: widget.selectedId == null,
                onTap: () => widget.onPick(null),
              ),
              ...filtered.map((s) {
                final id = s['id']?.toString();
                final sel = id != null && id == widget.selectedId;
                return ListTile(
                  title: Text(s['name']?.toString() ?? '—'),
                  selected: sel,
                  onTap: () => widget.onPick(id),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}
