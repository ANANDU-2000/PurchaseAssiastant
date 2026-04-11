import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/hexa_colors.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/contacts_hub_provider.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../shared/widgets/app_settings_action.dart';

Color _avatarColor(String seed) {
  const palette = <Color>[
    Color(0xFF1A6B8A),
    Color(0xFF0D3D56),
    Color(0xFF5C6BC0),
    Color(0xFF00897B),
    Color(0xFF6D4C41),
    Color(0xFFAD1457),
  ];
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final p = parts.first;
    return p.length >= 2 ? p.substring(0, 2).toUpperCase() : p[0].toUpperCase();
  }
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ContactsPage extends ConsumerStatefulWidget {
  const ContactsPage({super.key});

  @override
  ConsumerState<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends ConsumerState<ContactsPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _searchQuery = '';
  static const _searchMinLen = 2;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _scheduleSearch(String raw) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() => _searchQuery = raw.trim());
    });
  }

  bool get _isSearching => _searchQuery.length >= _searchMinLen;

  Future<void> _dial(String? phone) async {
    if (phone == null || phone.trim().isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'\s'), ''));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _addSupplier() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final loc = TextEditingController();
    final brokerId = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New supplier'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name *')),
              TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
              TextField(controller: loc, decoration: const InputDecoration(labelText: 'Location')),
              TextField(
                controller: brokerId,
                decoration: const InputDecoration(labelText: 'Broker ID (optional)', helperText: 'Paste UUID from Brokers tab'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final bid = brokerId.text.trim();
    try {
      await ref.read(hexaApiProvider).createSupplier(
            businessId: session.primaryBusiness.id,
            name: name.text.trim(),
            phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
            location: loc.text.trim().isEmpty ? null : loc.text.trim(),
            brokerId: bid.isEmpty ? null : bid,
          );
      ref.invalidate(suppliersListProvider);
      ref.invalidate(contactsSuppliersEnrichedProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Supplier created')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _addBroker() async {
    final name = TextEditingController();
    final comm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New broker'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name *')),
            TextField(
              controller: comm,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Commission value (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final v = double.tryParse(comm.text.trim());
      await ref.read(hexaApiProvider).createBroker(
            businessId: session.primaryBusiness.id,
            name: name.text.trim(),
            commissionValue: v,
          );
      ref.invalidate(brokersListProvider);
      ref.invalidate(contactsBrokersEnrichedProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Broker created')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _addCategorySheet() async {
    final nameCtrl = TextEditingController();
    final emojiCtrl = TextEditingController();
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 8,
            bottom: 24 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New category', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              TextField(
                controller: emojiCtrl,
                textAlign: TextAlign.center,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: 'Icon (emoji, optional)',
                  hintText: '🌾',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name *'),
                onSubmitted: (_) {
                  final n = nameCtrl.text.trim();
                  if (n.isEmpty) return;
                  final e = emojiCtrl.text.trim();
                  Navigator.pop(ctx, e.isEmpty ? n : '$e $n');
                },
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  final n = nameCtrl.text.trim();
                  if (n.isEmpty) return;
                  final e = emojiCtrl.text.trim();
                  Navigator.pop(ctx, e.isEmpty ? n : '$e $n');
                },
                child: const Text('Save category'),
              ),
            ],
          ),
        );
      },
    );
    nameCtrl.dispose();
    emojiCtrl.dispose();
    if (saved == null || saved.trim().isEmpty) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).createItemCategory(
            businessId: session.primaryBusiness.id,
            name: saved.trim(),
          );
      ref.invalidate(itemCategoriesListProvider);
      ref.invalidate(catalogItemsListProvider);
      ref.invalidate(contactsCategoriesProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category created')));
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.response?.data?.toString() ?? '$e')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _addItemSheet() async {
    List<Map<String, dynamic>> cats = [];
    try {
      cats = await ref.read(itemCategoriesListProvider.future);
    } catch (_) {}
    if (!mounted) return;
    if (cats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a category first (Categories tab).')),
      );
      return;
    }
    var selectedCat = cats.first['id']?.toString();
    final nameCtrl = TextEditingController();
    String? unit;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 8,
                bottom: 24 + MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('New item', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ValueKey(selectedCat),
                    initialValue: selectedCat,
                    decoration: const InputDecoration(labelText: 'Category *'),
                    items: cats
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c['id']?.toString(),
                            child: Text(c['name']?.toString() ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setSt(() => selectedCat = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Name *'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    key: ValueKey(unit),
                    initialValue: unit,
                    decoration: const InputDecoration(labelText: 'Default unit (optional)'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('—')),
                      DropdownMenuItem(value: 'kg', child: Text('kg')),
                      DropdownMenuItem(value: 'box', child: Text('box')),
                      DropdownMenuItem(value: 'piece', child: Text('pc')),
                      DropdownMenuItem(value: 'L', child: Text('L')),
                    ],
                    onChanged: (v) => setSt(() => unit = v),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Save item'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    final categoryId = selectedCat;
    if (saved != true || nameCtrl.text.trim().isEmpty || categoryId == null) {
      nameCtrl.dispose();
      return;
    }
    final session = ref.read(sessionProvider);
    if (session == null) {
      nameCtrl.dispose();
      return;
    }
    try {
      await ref.read(hexaApiProvider).createCatalogItem(
            businessId: session.primaryBusiness.id,
            categoryId: categoryId,
            name: nameCtrl.text.trim(),
            defaultUnit: unit,
          );
      ref.invalidate(catalogItemsListProvider);
      ref.invalidate(itemCategoriesListProvider);
      ref.invalidate(contactsItemsProvider);
      ref.invalidate(contactsCategoriesProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item created')));
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.response?.data?.toString() ?? '$e')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    nameCtrl.dispose();
  }

  Future<void> _editSupplier(Map<String, dynamic> s) async {
    final id = s['id']?.toString();
    if (id == null) return;
    final name = TextEditingController(text: s['name']?.toString() ?? '');
    final phone = TextEditingController(text: s['phone']?.toString() ?? '');
    final loc = TextEditingController(text: s['location']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit supplier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name *')),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
            TextField(controller: loc, decoration: const InputDecoration(labelText: 'Location')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).updateSupplier(
            businessId: session.primaryBusiness.id,
            supplierId: id,
            name: name.text.trim(),
            phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
            location: loc.text.trim().isEmpty ? null : loc.text.trim(),
          );
      ref.invalidate(suppliersListProvider);
      ref.invalidate(contactsSuppliersEnrichedProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteSupplier(Map<String, dynamic> s) async {
    final id = s['id']?.toString();
    if (id == null) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    if (session.primaryBusiness.role != 'owner') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only the workspace owner can delete.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete supplier?'),
        content: const Text('This cannot be undone. No purchase entries must reference this supplier.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(hexaApiProvider).deleteSupplier(businessId: session.primaryBusiness.id, supplierId: id);
      ref.invalidate(suppliersListProvider);
      ref.invalidate(contactsSuppliersEnrichedProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _editBroker(Map<String, dynamic> b) async {
    final id = b['id']?.toString();
    if (id == null) return;
    final name = TextEditingController(text: b['name']?.toString() ?? '');
    final comm = TextEditingController(text: b['commission_value']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit broker'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name *')),
            TextField(
              controller: comm,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Commission value'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).updateBroker(
            businessId: session.primaryBusiness.id,
            brokerId: id,
            name: name.text.trim(),
            commissionValue: double.tryParse(comm.text.trim()),
          );
      ref.invalidate(brokersListProvider);
      ref.invalidate(contactsBrokersEnrichedProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteBroker(Map<String, dynamic> b) async {
    final id = b['id']?.toString();
    if (id == null) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    if (session.primaryBusiness.role != 'owner') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only the workspace owner can delete.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete broker?'),
        content: const Text('Removes broker only if no entries or suppliers reference them.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(hexaApiProvider).deleteBroker(businessId: session.primaryBusiness.id, brokerId: id);
      ref.invalidate(brokersListProvider);
      ref.invalidate(contactsBrokersEnrichedProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _buildSearchResults() {
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey(_searchQuery),
      future: ref.read(hexaApiProvider).contactsSearch(businessId: session.primaryBusiness.id, query: _searchQuery),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        }
        final data = snap.data ?? {};
        final suppliers = (data['suppliers'] as List?) ?? [];
        final brokers = (data['brokers'] as List?) ?? [];
        final items = (data['item_names'] as List?) ?? [];
        final cats = (data['categories'] as List?) ?? [];
        if (suppliers.isEmpty && brokers.isEmpty && items.isEmpty && cats.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No matches. Try another keyword.'),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            if (suppliers.isNotEmpty) ...[
              Text('Suppliers', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ...suppliers.map((e) {
                final m = Map<String, dynamic>.from(e as Map);
                final id = m['id']?.toString();
                return ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(m['name']?.toString() ?? ''),
                  onTap: id == null ? null : () => context.push('/supplier/$id'),
                );
              }),
            ],
            if (brokers.isNotEmpty) ...[
              Text('Brokers', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ...brokers.map((e) {
                final m = Map<String, dynamic>.from(e as Map);
                final id = m['id']?.toString();
                return ListTile(
                  leading: const Icon(Icons.handshake_outlined),
                  title: Text(m['name']?.toString() ?? ''),
                  onTap: id == null ? null : () => context.push('/broker/$id'),
                );
              }),
            ],
            if (items.isNotEmpty) ...[
              Text('Items', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ...items.map((name) {
                final n = name.toString();
                return ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(n),
                  onTap: () => context.push('/item-analytics/${Uri.encodeComponent(n)}'),
                );
              }),
            ],
            if (cats.isNotEmpty) ...[
              Text('Categories', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ...cats.map((c) {
                final name = c.toString();
                return ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: Text(name),
                  onTap: () => context.push('/contacts/category?name=${Uri.encodeComponent(name)}'),
                );
              }),
            ],
          ],
        );
      },
    );
  }

  void _addForCurrentTab() {
    switch (_tabController.index) {
      case 0:
        _addSupplier();
        break;
      case 1:
        _addBroker();
        break;
      case 2:
        _addCategorySheet();
        break;
      default:
        _addItemSheet();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          const AppSettingsAction(),
          if (!_isSearching)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: AnimatedBuilder(
                animation: _tabController,
                builder: (context, _) {
                  final i = _tabController.index;
                  final tip = switch (i) {
                    0 => 'Add supplier',
                    1 => 'Add broker',
                    2 => 'Add category',
                    _ => 'Add item',
                  };
                  return IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: HexaColors.primaryMid,
                      foregroundColor: Colors.white,
                    ),
                    tooltip: tip,
                    onPressed: _addForCurrentTab,
                    icon: const Icon(Icons.add_rounded),
                  );
                },
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Material(
            color: cs.surface,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: HexaColors.borderSubtle)),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: const [
                  Tab(text: 'Suppliers'),
                  Tab(text: 'Brokers'),
                  Tab(text: 'Categories'),
                  Tab(text: 'Items'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _scheduleSearch,
              decoration: InputDecoration(
                hintText: 'Search suppliers, brokers, items, categories…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
            ),
          ),
          if (_isSearching)
            Expanded(
              child: SingleChildScrollView(child: _buildSearchResults()),
            )
          else
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _SuppliersTab(
                    onDial: _dial,
                    onEdit: _editSupplier,
                    onDelete: _deleteSupplier,
                  ),
                  _BrokersTab(
                    onEdit: _editBroker,
                    onDelete: _deleteBroker,
                  ),
                  _CategoriesTab(),
                  _ItemsTab(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SuppliersTab extends ConsumerWidget {
  const _SuppliersTab({required this.onDial, required this.onEdit, required this.onDelete});

  final void Function(String?) onDial;
  final Future<void> Function(Map<String, dynamic>) onEdit;
  final Future<void> Function(Map<String, dynamic>) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(contactsSuppliersEnrichedProvider);
    final session = ref.watch(sessionProvider);
    final isOwner = session?.primaryBusiness.role == 'owner';
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) {
        if (list.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(contactsSuppliersEnrichedProvider);
              await ref.read(contactsSuppliersEnrichedProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [SizedBox(height: 120, child: Center(child: Text('No suppliers yet')))],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(contactsSuppliersEnrichedProvider);
            await ref.read(contactsSuppliersEnrichedProvider.future);
          },
          child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final s = list[i];
            final id = s['id']?.toString();
            final m = s['_metrics'] as Map<String, dynamic>?;
            final deals = (m?['deals'] as num?)?.toInt();
            final avg = (m?['avg_landing'] as num?)?.toDouble();
            final profit = (m?['total_profit'] as num?)?.toDouble();
            final tq = (m?['total_qty'] as num?)?.toDouble() ?? 0;
            final nm = s['name']?.toString() ?? '';
            String marginStr = '—';
            if (m != null && tq > 0 && avg != null && avg > 0) {
              final cost = avg * tq;
              if (cost > 0) marginStr = '${((profit ?? 0) / cost * 100).toStringAsFixed(0)}%';
            }
            final phone = s['phone']?.toString();
            return Card(
              child: InkWell(
                onTap: id == null ? null : () => context.push('/supplier/$id'),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            backgroundColor: _avatarColor(nm.isEmpty ? 'x' : nm),
                            child: Text(
                              _initials(nm.isEmpty ? '?' : nm),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s['name']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                if (phone != null && phone.isNotEmpty) Text(phone, style: Theme.of(context).textTheme.bodySmall),
                                if (s['location'] != null && s['location'].toString().isNotEmpty)
                                  Text(s['location'].toString(), style: Theme.of(context).textTheme.bodySmall),
                                if (m != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Row(
                                      children: [
                                        _StatPill(icon: Icons.receipt_long_outlined, text: '${deals ?? 0} deals'),
                                        const SizedBox(width: 8),
                                        _StatPill(
                                          icon: Icons.currency_rupee_rounded,
                                          text: avg != null ? '₹${avg.toStringAsFixed(0)} avg' : '—',
                                        ),
                                        const SizedBox(width: 8),
                                        _StatPill(icon: Icons.percent_rounded, text: marginStr),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Call',
                            icon: const Icon(Icons.call_rounded),
                            onPressed: phone == null || phone.isEmpty ? null : () => onDial(phone),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') onEdit(s);
                              if (v == 'delete') onDelete(s);
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(value: 'edit', child: Text('Edit')),
                              if (isOwner) const PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        );
      },
    );
  }
}

class _BrokersTab extends ConsumerWidget {
  const _BrokersTab({required this.onEdit, required this.onDelete});

  final Future<void> Function(Map<String, dynamic>) onEdit;
  final Future<void> Function(Map<String, dynamic>) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(contactsBrokersEnrichedProvider);
    final session = ref.watch(sessionProvider);
    final isOwner = session?.primaryBusiness.role == 'owner';
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) {
        if (list.isEmpty) return const Center(child: Text('No brokers yet'));
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final b = list[i];
            final id = b['id']?.toString();
            final m = b['_metrics'] as Map<String, dynamic>?;
            final deals = (m?['deals'] as num?)?.toInt();
            final comm = (m?['total_commission'] as num?)?.toDouble();
            final profit = (m?['total_profit'] as num?)?.toDouble();
            final ct = b['commission_type']?.toString().toLowerCase() ?? '';
            final cv = b['commission_value'];
            final isPct = ct == 'percent';
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                  child: Icon(isPct ? Icons.percent_rounded : Icons.currency_rupee_rounded),
                ),
                title: Text(b['name']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Chip(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          label: Text(isPct ? '% per unit' : '₹ fixed', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.35)),
                        ),
                        if (cv != null) Text('$cv', style: Theme.of(context).textTheme.labelLarge),
                      ],
                    ),
                    if (m != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Deals: ${deals ?? 0} · Commission: ${comm?.toStringAsFixed(0) ?? '—'} · Profit: ${profit?.toStringAsFixed(0) ?? '—'}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') onEdit(b);
                    if (v == 'delete') onDelete(b);
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    if (isOwner) const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
                onTap: id == null ? null : () => context.push('/broker/$id'),
              ),
            );
          },
        );
      },
    );
  }
}

class _CategoriesTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(contactsCategoriesProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No categories in the last $contactsLookbackDays days'));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = rows[i];
            final name = r['category']?.toString() ?? '—';
            final profit = (r['total_profit'] as num?)?.toDouble() ?? 0;
            final lines = (r['line_count'] as num?)?.toInt() ?? 0;
            return Card(
              child: ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('Lines: $lines · Profit: ${profit.toStringAsFixed(0)}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/contacts/category?name=${Uri.encodeComponent(name)}'),
              ),
            );
          },
        );
      },
    );
  }
}

class _ItemsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(contactsItemsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No items in the last $contactsLookbackDays days'));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = rows[i];
            final name = r['item_name']?.toString() ?? '—';
            final avg = (r['avg_landing'] as num?)?.toDouble() ?? 0;
            final profit = (r['total_profit'] as num?)?.toDouble() ?? 0;
            final lc = (r['line_count'] as num?)?.toInt() ?? 0;
            return Card(
              child: ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('Lines: $lc · Avg landing: ${avg.toStringAsFixed(1)} · Profit: ${profit.toStringAsFixed(0)}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/item-analytics/${Uri.encodeComponent(name)}'),
              ),
            );
          },
        );
      },
    );
  }
}
