import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/contacts_hub_provider.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/search/search_highlight.dart';
import '../../../shared/widgets/app_settings_action.dart';
import 'broker_wizard_page.dart';
import 'supplier_create_wizard_page.dart';

String _fmtBrokerCommissionPct(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

String _fmtBrokerCommissionInr(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(0);

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
  final parts =
      name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final p = parts.first;
    return p.length >= 2 ? p.substring(0, 2).toUpperCase() : p[0].toUpperCase();
  }
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

/// Supplier row — name, phone, WhatsApp and a ⋮ menu. No analytics clutter.
class _SupplierCard extends StatelessWidget {
  const _SupplierCard({
    required this.data,
    required this.metrics,
    required this.onOpen,
    required this.onDial,
    required this.onWhatsApp,
    required this.onEdit,
    required this.onDelete,
    this.highlightQuery = '',
  });

  final Map<String, dynamic> data;
  final Map<String, dynamic>? metrics;
  final String highlightQuery;
  final VoidCallback onOpen;
  final void Function(String? phone) onDial;
  final void Function(String? wa) onWhatsApp;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final id = data['id']?.toString();
    final nm = data['name']?.toString() ?? '—';
    final phone = data['phone']?.toString();
    final wa = data['whatsapp_number']?.toString();
    final loc = data['location']?.toString() ?? '';
    final titleBase =
        tt.titleMedium?.copyWith(fontWeight: FontWeight.w800) ?? const TextStyle(fontWeight: FontWeight.w800);
    final locBase = tt.bodySmall?.copyWith(color: HexaColors.textSecondary) ??
        const TextStyle(color: HexaColors.textSecondary);
    final hlStyle = TextStyle(
      fontWeight: FontWeight.w900,
      color: cs.primary,
      backgroundColor: cs.primaryContainer.withValues(alpha: 0.4),
    );
    final locHlStyle = locBase.copyWith(
      fontWeight: FontWeight.w800,
      color: cs.primary,
      backgroundColor: cs.primaryContainer.withValues(alpha: 0.35),
    );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: HexaColors.border),
      ),
      child: InkWell(
        onTap: id == null ? null : onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: _avatarColor(nm.isEmpty ? 'x' : nm),
                    child: Text(
                      _initials(nm.isEmpty ? '?' : nm),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: highlightSearchQuery(
                              nm,
                              highlightQuery,
                              baseStyle: titleBase,
                              highlightStyle: hlStyle,
                            ),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (loc.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.place_outlined,
                                    size: 16, color: HexaColors.textSecondary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      children: highlightSearchQuery(
                                        loc,
                                        highlightQuery,
                                        baseStyle: locBase,
                                        highlightStyle: locHlStyle,
                                      ),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (phone != null && phone.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: InkWell(
                              onTap: () => onDial(phone),
                              child: Row(
                                children: [
                                  const Icon(Icons.phone_outlined,
                                      size: 16, color: HexaColors.primaryMid),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Tap to call',
                                    style: tt.labelLarge?.copyWith(
                                        color: HexaColors.primaryMid,
                                        fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(phone, style: tt.bodySmall),
                                ],
                              ),
                            ),
                          ),
                        if (wa != null && wa.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: InkWell(
                              onTap: () => onWhatsApp(wa),
                              child: Row(
                                children: [
                                  const Icon(Icons.chat_rounded,
                                      size: 16, color: Color(0xFF25D366)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'WhatsApp',
                                    style: tt.labelLarge?.copyWith(
                                      color: const Color(0xFF128C7E),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(wa, style: tt.bodySmall),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (v) {
                      if (v == 'detail') onOpen();
                      if (v == 'edit') onEdit();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                          value: 'detail', child: Text('View detail')),
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(
                          value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrokerCard extends StatelessWidget {
  const _BrokerCard({
    required this.data,
    required this.metrics,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    this.highlightQuery = '',
  });

  final Map<String, dynamic> data;
  final Map<String, dynamic>? metrics;
  final String highlightQuery;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final id = data['id']?.toString();
    final ct = data['commission_type']?.toString().toLowerCase() ?? '';
    final cv = data['commission_value'];
    final isPct = ct == 'percent';
    final cvNum = (cv is num) ? cv.toDouble() : double.tryParse(cv?.toString() ?? '');
    final nm = data['name']?.toString() ?? '—';
    final titleBase =
        tt.titleMedium?.copyWith(fontWeight: FontWeight.w800) ?? const TextStyle(fontWeight: FontWeight.w800);
    final hlStyle = TextStyle(
      fontWeight: FontWeight.w900,
      color: cs.primary,
      backgroundColor: cs.primaryContainer.withValues(alpha: 0.4),
    );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: HexaColors.border),
      ),
      child: InkWell(
        onTap: id == null ? null : onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: cs.secondaryContainer,
                    child: Icon(isPct
                        ? Icons.percent_rounded
                        : Icons.currency_rupee_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: highlightSearchQuery(
                              nm,
                              highlightQuery,
                              baseStyle: titleBase,
                              highlightStyle: hlStyle,
                            ),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isPct
                              ? (cvNum == null
                                  ? 'Commission: —'
                                  : 'Commission: ${_fmtBrokerCommissionPct(cvNum)}%')
                              : (cvNum == null
                                  ? 'Commission: —'
                                  : 'Commission: Fixed ₹${_fmtBrokerCommissionInr(cvNum)}'),
                          style: tt.bodySmall
                              ?.copyWith(color: HexaColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (v) {
                      if (v == 'detail') onOpen();
                      if (v == 'edit') onEdit();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                          value: 'detail', child: Text('View detail')),
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(
                          value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
            ],
          ),
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

class _ContactsPageState extends ConsumerState<ContactsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _searchQuery = '';
  Map<String, dynamic>? _searchSnapshot;
  bool _searchLoading = false;
  /// Bumped when a new search is scheduled or cleared; stale HTTP responses are ignored.
  int _contactsSearchSeq = 0;
  static const _searchMinLen = 1;

  static String _scopeForTab(int tabIndex) {
    const scopes = ['suppliers', 'brokers', 'categories', 'catalog_types', 'items'];
    if (tabIndex < 0 || tabIndex >= scopes.length) return 'all';
    return scopes[tabIndex];
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging || !mounted) return;
    setState(() {});
    final q = _searchCtrl.text.trim();
    if (q.length >= _searchMinLen) {
      _debounce?.cancel();
      _scheduleSearch(q);
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _contactsSearchSeq++;
    _tabController.removeListener(_onTabChanged);
    _debounce?.cancel();
    _searchCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _scheduleSearch(String raw) {
    _debounce?.cancel();
    final t = raw.trim();
    if (t.length < _searchMinLen) {
      _contactsSearchSeq++;
      setState(() {
        _searchQuery = '';
        _searchSnapshot = null;
        _searchLoading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 180), () async {
      if (!mounted) return;
      final session = ref.read(sessionProvider);
      if (session == null) {
        if (mounted) {
          setState(() => _searchLoading = false);
        }
        return;
      }
      // Read tab when the request runs — not when the timer was scheduled — so scope
      // matches the visible tab if the user switched tabs during debounce.
      final scopeTab = _tabController.index;
      final seq = ++_contactsSearchSeq;
      setState(() {
        _searchQuery = t;
        _searchLoading = true;
      });
      try {
        final data = await ref.read(hexaApiProvider).contactsSearch(
              businessId: session.primaryBusiness.id,
              query: t,
              scope: _scopeForTab(scopeTab),
            );
        if (!mounted || seq != _contactsSearchSeq) return;
        setState(() {
          _searchSnapshot = data;
          _searchLoading = false;
        });
      } catch (e) {
        if (!mounted || seq != _contactsSearchSeq) return;
        setState(() => _searchLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
        }
      }
    });
  }

  bool get _isSearching => _searchQuery.length >= _searchMinLen;

  int _searchCountForTab(int i) {
    final d = _searchSnapshot;
    if (d == null) return 0;
    switch (i) {
      case 0:
        return ((d['suppliers'] as List?) ?? []).length;
      case 1:
        return ((d['brokers'] as List?) ?? []).length;
      case 2:
        return ((d['categories'] as List?) ?? []).length;
      case 3:
        return ((d['catalog_subcategories'] as List?) ?? []).length;
      case 4:
        return ((d['item_names'] as List?) ?? []).length;
      default:
        return 0;
    }
  }

  Future<void> _dial(String? phone) async {
    if (phone == null || phone.trim().isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'\s'), ''));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openWhatsApp(String? raw) async {
    if (raw == null || raw.trim().isEmpty) return;
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return;
    final uri = Uri.parse('https://wa.me/$d');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _addSupplier() async {
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => const SupplierCreateWizardPage(),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _addBroker() async {
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => const BrokerWizardPage(),
        fullscreenDialog: true,
      ),
    );
    if (!mounted) return;
    ref.invalidate(brokersListProvider);
    ref.invalidate(contactsBrokersEnrichedProvider);
  }

  Future<void> _addCategorySheet() async {
    final nameCtrl = TextEditingController();
    final emojiCtrl = TextEditingController();
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
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
              Text('New category',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Category created')));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }

  Future<void> _addItemSheet() async {
    if (!mounted) return;
    await context.push<String?>('/catalog');
    if (!mounted) return;
    ref.invalidate(catalogItemsListProvider);
    ref.invalidate(itemCategoriesListProvider);
    ref.invalidate(contactsSuppliersEnrichedProvider);
    ref.invalidate(contactsBrokersEnrichedProvider);
  }

  Future<void> _editSupplier(Map<String, dynamic> s) async {
    final id = s['id']?.toString();
    if (id == null) return;
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => SupplierCreateWizardPage(supplierId: id),
        fullscreenDialog: true,
      ),
    );
    if (!mounted) return;
    ref.invalidate(suppliersListProvider);
    ref.invalidate(contactsSuppliersEnrichedProvider);
  }

  Future<void> _deleteSupplier(Map<String, dynamic> s) async {
    final id = s['id']?.toString();
    if (id == null) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    if (session.primaryBusiness.role != 'owner') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Only the workspace owner can delete.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete supplier?'),
        content: const Text(
            'This cannot be undone. No purchase entries must reference this supplier.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(hexaApiProvider).deleteSupplier(
          businessId: session.primaryBusiness.id, supplierId: id);
      ref.invalidate(suppliersListProvider);
      ref.invalidate(contactsSuppliersEnrichedProvider);
      invalidateTradePurchaseCaches(ref);
      invalidateBusinessAggregates(ref);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }

  Future<void> _editBroker(Map<String, dynamic> b) async {
    final id = b['id']?.toString();
    if (id == null) return;
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => BrokerWizardPage(brokerId: id),
        fullscreenDialog: true,
      ),
    );
    if (!mounted) return;
    ref.invalidate(brokersListProvider);
    ref.invalidate(contactsBrokersEnrichedProvider);
  }

  Future<void> _deleteBroker(Map<String, dynamic> b) async {
    final id = b['id']?.toString();
    if (id == null) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    if (session.primaryBusiness.role != 'owner') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Only the workspace owner can delete.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete broker?'),
        content: const Text(
            'Removes broker only if no entries or suppliers reference them.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(hexaApiProvider)
          .deleteBroker(businessId: session.primaryBusiness.id, brokerId: id);
      ref.invalidate(brokersListProvider);
      ref.invalidate(contactsBrokersEnrichedProvider);
      invalidateTradePurchaseCaches(ref);
      invalidateBusinessAggregates(ref);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }

  Widget _tabWithBadge(String label, int count) {
    final c = count > 0 ? count : null;
    return Tab(
      child: Badge(
        isLabelVisible: c != null,
        label: Text(c == null ? '' : '$c',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }

  Widget _searchResultsForTab(int tabIndex) {
    final d = _searchSnapshot ?? {};
    final tt = Theme.of(context).textTheme;
    switch (tabIndex) {
      case 0:
        final suppliers = (d['suppliers'] as List?) ?? [];
        if (suppliers.isEmpty) {
          return Center(
              child: Text('No supplier matches.',
                  style: tt.bodyMedium
                      ?.copyWith(color: HexaColors.textSecondary)));
        }
        return ListView.separated(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: suppliers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final m = Map<String, dynamic>.from(suppliers[i] as Map);
            final id = m['id']?.toString();
            return _SupplierCard(
              data: m,
              metrics: null,
              highlightQuery: _searchQuery,
              onOpen: id == null ? () {} : () => context.push('/supplier/$id'),
              onDial: _dial,
              onWhatsApp: _openWhatsApp,
              onEdit: () => _editSupplier(m),
              onDelete: () => _deleteSupplier(m),
            );
          },
        );
      case 1:
        final brokers = (d['brokers'] as List?) ?? [];
        if (brokers.isEmpty) {
          return Center(
              child: Text('No broker matches.',
                  style: tt.bodyMedium
                      ?.copyWith(color: HexaColors.textSecondary)));
        }
        return ListView.separated(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: brokers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final b = Map<String, dynamic>.from(brokers[i] as Map);
            final id = b['id']?.toString();
            return _BrokerCard(
              data: b,
              metrics: null,
              highlightQuery: _searchQuery,
              onOpen: id == null ? () {} : () => context.push('/broker/$id'),
              onEdit: () => _editBroker(b),
              onDelete: () => _deleteBroker(b),
            );
          },
        );
      case 2:
        final cats = (d['categories'] as List?) ?? [];
        if (cats.isEmpty) {
          return Center(
              child: Text('No category matches.',
                  style: tt.bodyMedium
                      ?.copyWith(color: HexaColors.textSecondary)));
        }
        return ListView.separated(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: cats.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final name = cats[i].toString();
            final cs = Theme.of(context).colorScheme;
            return Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: HexaColors.border)),
              child: ListTile(
                leading: const Icon(Icons.folder_outlined,
                    color: HexaColors.primaryMid),
                title: Text.rich(
                  TextSpan(
                    children: highlightSearchQuery(
                      name,
                      _searchQuery,
                      baseStyle: const TextStyle(fontWeight: FontWeight.w700),
                      highlightStyle: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: cs.primary,
                        backgroundColor:
                            cs.primaryContainer.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: const Text('Purchase line category (from history)'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(
                    '/contacts/category?name=${Uri.encodeComponent(name)}'),
              ),
            );
          },
        );
      case 3:
        final subs = (d['catalog_subcategories'] as List?) ?? [];
        if (subs.isEmpty) {
          return Center(
              child: Text('No catalog type matches.',
                  style: tt.bodyMedium
                      ?.copyWith(color: HexaColors.textSecondary)));
        }
        return ListView.separated(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: subs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final m = Map<String, dynamic>.from(subs[i] as Map);
            final tid = m['id']?.toString() ?? '';
            final cid = m['category_id']?.toString() ?? '';
            final tname = m['name']?.toString() ?? '—';
            final cname = m['category_name']?.toString() ?? '';
            final cs = Theme.of(context).colorScheme;
            return Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: HexaColors.border)),
              child: ListTile(
                leading: const Icon(Icons.category_outlined,
                    color: HexaColors.primaryMid),
                title: Text.rich(
                  TextSpan(
                    children: highlightSearchQuery(
                      tname,
                      _searchQuery,
                      baseStyle: const TextStyle(fontWeight: FontWeight.w700),
                      highlightStyle: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: cs.primary,
                        backgroundColor:
                            cs.primaryContainer.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  cname.isNotEmpty ? 'In $cname' : 'Catalog type',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: tid.isEmpty || cid.isEmpty
                    ? null
                    : () => context.push('/catalog/category/$cid/type/$tid'),
              ),
            );
          },
        );
      case 4:
        final items = (d['item_names'] as List?) ?? [];
        if (items.isEmpty) {
          return Center(
              child: Text('No item name matches.',
                  style: tt.bodyMedium
                      ?.copyWith(color: HexaColors.textSecondary)));
        }
        return ListView.separated(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final n = items[i].toString();
            final cs = Theme.of(context).colorScheme;
            return Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: HexaColors.border)),
              child: ListTile(
                leading: const Icon(Icons.inventory_2_outlined,
                    color: HexaColors.primaryMid),
                title: Text.rich(
                  TextSpan(
                    children: highlightSearchQuery(
                      n,
                      _searchQuery,
                      baseStyle: const TextStyle(fontWeight: FontWeight.w700),
                      highlightStyle: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: cs.primary,
                        backgroundColor:
                            cs.primaryContainer.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: const Text('Item analytics'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () =>
                    context.push('/item-analytics/${Uri.encodeComponent(n)}'),
              ),
            );
          },
        );
      default:
        return const SizedBox.shrink();
    }
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
      case 3:
        if (!mounted) return;
        context.push('/catalog');
        break;
      default:
        _addItemSheet();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Contacts',
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              'Suppliers · brokers · categories · catalog types · item names.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Item catalog (units, variants)',
            onPressed: () => context.push('/catalog'),
            icon: const Icon(Icons.inventory_2_outlined),
          ),
          IconButton(
            tooltip: 'Add',
            onPressed: _addForCurrentTab,
            icon: const Icon(Icons.add_rounded),
          ),
          const AppSettingsAction(),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Material(
            color: cs.surface,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: HexaColors.borderSubtle)),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  _tabWithBadge('Suppliers', _searchCountForTab(0)),
                  _tabWithBadge('Brokers', _searchCountForTab(1)),
                  _tabWithBadge('Categories', _searchCountForTab(2)),
                  _tabWithBadge('Types', _searchCountForTab(3)),
                  _tabWithBadge('Items', _searchCountForTab(4)),
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
                hintText: 'Search (name, phone, type…) — 1+ characters',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchCtrl,
                  builder: (_, val, __) {
                    if (val.text.isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        _scheduleSearch('');
                      },
                    );
                  },
                ),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
            ),
          ),
          Expanded(
            child: _isSearching
                ? (_searchLoading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _searchResultsForTab(0),
                          _searchResultsForTab(1),
                          _searchResultsForTab(2),
                          _searchResultsForTab(3),
                          _searchResultsForTab(4),
                        ],
                      ))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _SuppliersTab(
                        onDial: _dial,
                        onWhatsApp: _openWhatsApp,
                        onEdit: _editSupplier,
                        onDelete: _deleteSupplier,
                      ),
                      _BrokersTab(
                        onEdit: _editBroker,
                        onDelete: _deleteBroker,
                      ),
                      _CategoriesTab(),
                      const _CatalogTypesBrowseHint(),
                      _ItemsTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CatalogTypesBrowseHint extends StatelessWidget {
  const _CatalogTypesBrowseHint();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Catalog types',
              textAlign: TextAlign.center,
              style:
                  tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'Subcategories (e.g. rice type) live under Categories in Catalog. Manage structure there; search finds types on the Types tab.',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: sub, height: 1.35),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () => context.push('/catalog'),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open catalog'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuppliersTab extends ConsumerStatefulWidget {
  const _SuppliersTab({
    required this.onDial,
    required this.onWhatsApp,
    required this.onEdit,
    required this.onDelete,
  });

  final void Function(String?) onDial;
  final void Function(String?) onWhatsApp;
  final Future<void> Function(Map<String, dynamic>) onEdit;
  final Future<void> Function(Map<String, dynamic>) onDelete;

  @override
  ConsumerState<_SuppliersTab> createState() => _SuppliersTabState();
}

class _SuppliersTabState extends ConsumerState<_SuppliersTab> {
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(contactsSuppliersEnrichedProvider);
    return async.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () => const ListSkeleton(),
      error: (_, __) => FriendlyLoadError(
        onRetry: () => ref.invalidate(contactsSuppliersEnrichedProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(contactsSuppliersEnrichedProvider);
              await ref.read(contactsSuppliersEnrichedProvider.future);
            },
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              children: const [
                SizedBox(
                    height: 120, child: Center(child: Text('No suppliers yet')))
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(contactsSuppliersEnrichedProvider);
            await ref.read(contactsSuppliersEnrichedProvider.future);
          },
          child: ListView.separated(
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final s = list[i];
              final id = s['id']?.toString();
              final m = s['_metrics'] as Map<String, dynamic>?;
              return _SupplierCard(
                data: Map<String, dynamic>.from(s),
                metrics: m,
                onOpen: id == null
                    ? () {}
                    : () => context.push('/supplier/$id'),
                onDial: widget.onDial,
                onWhatsApp: widget.onWhatsApp,
                onEdit: () => widget.onEdit(s),
                onDelete: () => widget.onDelete(s),
              );
            },
          ),
        );
      },
    );
  }
}

class _BrokersTab extends ConsumerStatefulWidget {
  const _BrokersTab({required this.onEdit, required this.onDelete});

  final Future<void> Function(Map<String, dynamic>) onEdit;
  final Future<void> Function(Map<String, dynamic>) onDelete;

  @override
  ConsumerState<_BrokersTab> createState() => _BrokersTabState();
}

class _BrokersTabState extends ConsumerState<_BrokersTab> {
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(contactsBrokersEnrichedProvider);
    return async.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () => const ListSkeleton(),
      error: (_, __) => FriendlyLoadError(
        onRetry: () => ref.invalidate(contactsBrokersEnrichedProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(contactsBrokersEnrichedProvider);
              await ref.read(contactsBrokersEnrichedProvider.future);
            },
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              children: const [
                SizedBox(
                  height: 120,
                  child: Center(child: Text('No brokers yet')),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(contactsBrokersEnrichedProvider);
            await ref.read(contactsBrokersEnrichedProvider.future);
          },
          child: ListView.separated(
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final b = list[i];
              final id = b['id']?.toString();
              final m = b['_metrics'] as Map<String, dynamic>?;
              return _BrokerCard(
                data: Map<String, dynamic>.from(b),
                metrics: m,
                onOpen: id == null
                    ? () {}
                    : () => context.push('/broker/$id'),
                onEdit: () => widget.onEdit(b),
                onDelete: () => widget.onDelete(b),
              );
            },
          ),
        );
      },
    );
  }
}

class _CategoriesTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catsAsync = ref.watch(itemCategoriesListProvider);
    final itemsAsync = ref.watch(catalogItemsListProvider);
    return catsAsync.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => FriendlyLoadError(
        onRetry: () {
          ref.invalidate(itemCategoriesListProvider);
          ref.invalidate(catalogItemsListProvider);
        },
      ),
      data: (cats) {
        return itemsAsync.when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => FriendlyLoadError(
            onRetry: () {
              ref.invalidate(itemCategoriesListProvider);
              ref.invalidate(catalogItemsListProvider);
            },
          ),
          data: (items) {
            if (cats.isEmpty) {
              final cs = Theme.of(context).colorScheme;
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(itemCategoriesListProvider);
                  ref.invalidate(catalogItemsListProvider);
                  await ref.read(itemCategoriesListProvider.future);
                },
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.all(24),
                  children: [
                    SizedBox(
                      height: 200,
                      child: Center(
                        child: Text(
                          'No categories yet. Use ＋ Category to add one — same list as Settings → Item catalog.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return ListView.separated(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: cats.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final c = cats[i];
                final id = c['id']?.toString() ?? '';
                final name = c['name']?.toString() ?? '—';
                final nItems = items
                    .where((it) => it['category_id']?.toString() == id)
                    .length;
                final cs = Theme.of(context).colorScheme;
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.65)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    leading: const CircleAvatar(
                      backgroundColor: HexaColors.primaryLight,
                      child: Icon(Icons.grass_outlined,
                          color: HexaColors.primaryMid),
                    ),
                    title: Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                      '$nItems items · tap to see items',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    trailing: Icon(Icons.chevron_right_rounded,
                        color: cs.onSurfaceVariant),
                    onTap: () => context.push('/catalog/category/$id'),
                  ),
                );
              },
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
    final catsAsync = ref.watch(itemCategoriesListProvider);
    final itemsAsync = ref.watch(catalogItemsListProvider);
    return catsAsync.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => FriendlyLoadError(
        onRetry: () {
          ref.invalidate(itemCategoriesListProvider);
          ref.invalidate(catalogItemsListProvider);
        },
      ),
      data: (cats) {
        final catName = <String, String>{
          for (final x in cats) x['id'].toString(): x['name'].toString(),
        };
        return itemsAsync.when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => FriendlyLoadError(
            onRetry: () {
              ref.invalidate(itemCategoriesListProvider);
              ref.invalidate(catalogItemsListProvider);
            },
          ),
          data: (items) {
            if (items.isEmpty) {
              final cs = Theme.of(context).colorScheme;
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(itemCategoriesListProvider);
                  ref.invalidate(catalogItemsListProvider);
                  await ref.read(itemCategoriesListProvider.future);
                  await ref.read(catalogItemsListProvider.future);
                },
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.all(24),
                  children: [
                    SizedBox(
                      height: 200,
                      child: Center(
                        child: Text(
                          'No catalog items yet. Use ＋ Item or Settings → Item catalog.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return ListView.separated(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final it = items[i];
                final id = it['id']?.toString() ?? '';
                final name = it['name']?.toString() ?? '—';
                final cid = it['category_id']?.toString() ?? '';
                final du = it['default_unit']?.toString();
                final sub =
                    '${catName[cid] ?? '—'}${du != null && du.isNotEmpty ? ' · default: $du' : ''}';
                final cs = Theme.of(context).colorScheme;
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.65)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    leading: const CircleAvatar(
                      backgroundColor: HexaColors.primaryLight,
                      child: Icon(Icons.inventory_2_outlined,
                          color: HexaColors.primaryMid),
                    ),
                    title: Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                      sub,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    trailing: Icon(Icons.chevron_right_rounded,
                        color: cs.onSurfaceVariant),
                    onTap: () => context.push('/catalog/item/$id'),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
