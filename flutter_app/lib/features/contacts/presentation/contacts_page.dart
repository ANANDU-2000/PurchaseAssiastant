import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/contacts_hub_provider.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../shared/widgets/app_settings_action.dart';
import '../../../shared/widgets/bag_default_unit_hint.dart';

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
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Supplier row — optional [metrics] from contacts hub (null in global search).
class _SupplierCard extends StatelessWidget {
  const _SupplierCard({
    required this.data,
    required this.metrics,
    required this.isOwner,
    required this.onOpen,
    required this.onDial,
    required this.onWhatsApp,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> data;
  final Map<String, dynamic>? metrics;
  final bool isOwner;
  final VoidCallback onOpen;
  final void Function(String? phone) onDial;
  final void Function(String? wa) onWhatsApp;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final id = data['id']?.toString();
    final m = metrics;
    final deals = (m?['deals'] as num?)?.toInt();
    final avg = (m?['avg_landing'] as num?)?.toDouble();
    final profit = (m?['total_profit'] as num?)?.toDouble();
    final tq = (m?['total_qty'] as num?)?.toDouble() ?? 0;
    final nm = data['name']?.toString() ?? '—';
    var marginStr = '—';
    if (m != null && tq > 0 && avg != null && avg > 0) {
      final cost = avg * tq;
      if (cost > 0) {
        marginStr = '${((profit ?? 0) / cost * 100).toStringAsFixed(0)}%';
      }
    }
    final phone = data['phone']?.toString();
    final wa = data['whatsapp_number']?.toString();
    final loc = data['location']?.toString() ?? '';

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
                        Text(nm,
                            style: tt.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        if (loc.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.place_outlined,
                                    size: 16, color: HexaColors.textSecondary),
                                const SizedBox(width: 4),
                                Expanded(
                                    child: Text(loc,
                                        style: tt.bodySmall?.copyWith(
                                            color: HexaColors.textSecondary))),
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
                      if (isOwner)
                        const PopupMenuItem(
                            value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              Row(
                children: [
                  _StatPill(
                      icon: Icons.local_shipping_outlined,
                      text: 'Deals: ${deals ?? 0}'),
                  const SizedBox(width: 8),
                  _StatPill(
                    icon: Icons.currency_rupee_rounded,
                    text: avg != null
                        ? 'Avg: ₹${avg.toStringAsFixed(0)}'
                        : 'Avg: —',
                  ),
                  const SizedBox(width: 8),
                  _StatPill(
                      icon: Icons.percent_rounded, text: 'Margin: $marginStr'),
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
    required this.isOwner,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> data;
  final Map<String, dynamic>? metrics;
  final bool isOwner;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final id = data['id']?.toString();
    final m = metrics;
    final deals = (m?['deals'] as num?)?.toInt();
    final comm = (m?['total_commission'] as num?)?.toDouble();
    final profit = (m?['total_profit'] as num?)?.toDouble();
    final ct = data['commission_type']?.toString().toLowerCase() ?? '';
    final cv = data['commission_value'];
    final isPct = ct == 'percent';
    final nm = data['name']?.toString() ?? '—';

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
                    backgroundColor:
                        Theme.of(context).colorScheme.secondaryContainer,
                    child: Icon(isPct
                        ? Icons.percent_rounded
                        : Icons.currency_rupee_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nm,
                            style: tt.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          isPct
                              ? 'Commission: Per cent'
                              : 'Commission: Fixed ₹',
                          style: tt.bodySmall
                              ?.copyWith(color: HexaColors.textSecondary),
                        ),
                        if (cv != null)
                          Text('$cv',
                              style: tt.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w600)),
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
                      if (isOwner)
                        const PopupMenuItem(
                            value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              Row(
                children: [
                  _StatPill(
                      icon: Icons.receipt_long_outlined,
                      text: 'Deals: ${deals ?? 0}'),
                  const SizedBox(width: 8),
                  _StatPill(
                    icon: Icons.payments_outlined,
                    text: comm != null
                        ? 'Commission: ₹${comm.toStringAsFixed(0)}'
                        : 'Commission: —',
                  ),
                  const SizedBox(width: 8),
                  _StatPill(
                    icon: Icons.trending_up_rounded,
                    text: profit != null
                        ? 'Impact: ₹${profit.toStringAsFixed(0)}'
                        : 'Impact: —',
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
  static const _searchMinLen = 2;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() => setState(() {}));
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
    final t = raw.trim();
    if (t.length < _searchMinLen) {
      setState(() {
        _searchQuery = '';
        _searchSnapshot = null;
        _searchLoading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      final session = ref.read(sessionProvider);
      if (session == null) return;
      setState(() {
        _searchQuery = t;
        _searchLoading = true;
      });
      try {
        final data = await ref.read(hexaApiProvider).contactsSearch(
              businessId: session.primaryBusiness.id,
              query: t,
            );
        if (!mounted) return;
        setState(() {
          _searchSnapshot = data;
          _searchLoading = false;
        });
      } catch (e) {
        if (!mounted) return;
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
      default:
        return ((d['item_names'] as List?) ?? []).length;
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
    final name = TextEditingController();
    final phone = TextEditingController();
    final wa = TextEditingController();
    final loc = TextEditingController();
    String? selectedBrokerId;
    List<Map<String, dynamic>> brokers = [];
    try {
      brokers = await ref.read(brokersListProvider.future);
    } catch (_) {
      brokers = [];
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('New supplier'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name *')),
                TextField(
                    controller: phone,
                    decoration: const InputDecoration(labelText: 'Phone')),
                TextField(
                  controller: wa,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp number',
                    helperText: 'Optional — can differ from phone',
                  ),
                ),
                TextField(
                    controller: loc,
                    decoration: const InputDecoration(labelText: 'Location')),
                DropdownButtonFormField<String?>(
                  key: ValueKey(selectedBrokerId ?? '∅'),
                  initialValue: selectedBrokerId,
                  decoration:
                      const InputDecoration(labelText: 'Broker (optional)'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('None')),
                    ...brokers.map(
                      (b) => DropdownMenuItem<String?>(
                        value: b['id']?.toString(),
                        child: Text(b['name']?.toString() ?? ''),
                      ),
                    ),
                  ],
                  onChanged: (v) => setSt(() => selectedBrokerId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).createSupplier(
            businessId: session.primaryBusiness.id,
            name: name.text.trim(),
            phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
            whatsappNumber: wa.text.trim().isEmpty ? null : wa.text.trim(),
            location: loc.text.trim().isEmpty ? null : loc.text.trim(),
            brokerId: selectedBrokerId,
          );
      ref.invalidate(suppliersListProvider);
      ref.invalidate(contactsSuppliersEnrichedProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Supplier created')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
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
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name *')),
            TextField(
              controller: comm,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Commission value (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Broker created')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
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
    List<Map<String, dynamic>> cats = [];
    try {
      cats = await ref.read(itemCategoriesListProvider.future);
    } catch (_) {}
    if (!mounted) return;
    if (cats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Create a category first (Categories tab).')),
      );
      return;
    }
    var selectedCat = cats.first['id']?.toString();
    final nameCtrl = TextEditingController();
    final kgCtrl = TextEditingController();
    String? unit;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
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
                  Text('New item',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
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
                    decoration: const InputDecoration(
                        labelText: 'Default unit (optional)'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('—')),
                      DropdownMenuItem(value: 'kg', child: Text('kg')),
                      DropdownMenuItem(value: 'bag', child: Text('bag')),
                      DropdownMenuItem(value: 'box', child: Text('box')),
                      DropdownMenuItem(value: 'piece', child: Text('pc')),
                    ],
                    onChanged: (v) => setSt(() => unit = v),
                  ),
                  if (unit == 'bag') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: kgCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Default kg per bag (optional)',
                        hintText: 'e.g. 50',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const BagDefaultUnitHint(),
                  ],
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
      kgCtrl.dispose();
      return;
    }
    final session = ref.read(sessionProvider);
    if (session == null) {
      nameCtrl.dispose();
      kgCtrl.dispose();
      return;
    }
    try {
      await ref.read(hexaApiProvider).createCatalogItem(
            businessId: session.primaryBusiness.id,
            categoryId: categoryId,
            name: nameCtrl.text.trim(),
            defaultUnit: unit,
            defaultKgPerBag:
                unit == 'bag' ? parseOptionalKgPerBag(kgCtrl.text) : null,
          );
      ref.invalidate(catalogItemsListProvider);
      ref.invalidate(itemCategoriesListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Item created')));
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
    nameCtrl.dispose();
    kgCtrl.dispose();
  }

  Future<void> _editSupplier(Map<String, dynamic> s) async {
    final id = s['id']?.toString();
    if (id == null) return;
    final name = TextEditingController(text: s['name']?.toString() ?? '');
    final phone = TextEditingController(text: s['phone']?.toString() ?? '');
    final wa =
        TextEditingController(text: s['whatsapp_number']?.toString() ?? '');
    final loc = TextEditingController(text: s['location']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit supplier'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name *')),
              TextField(
                  controller: phone,
                  decoration: const InputDecoration(labelText: 'Phone')),
              TextField(
                controller: wa,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'WhatsApp number'),
              ),
              TextField(
                  controller: loc,
                  decoration: const InputDecoration(labelText: 'Location')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
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
            whatsappNumber: wa.text.trim(),
            location: loc.text.trim().isEmpty ? null : loc.text.trim(),
          );
      ref.invalidate(suppliersListProvider);
      ref.invalidate(contactsSuppliersEnrichedProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
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
    final name = TextEditingController(text: b['name']?.toString() ?? '');
    final comm =
        TextEditingController(text: b['commission_value']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit broker'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name *')),
            TextField(
              controller: comm,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Commission value'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
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

  Widget _searchResultsForTab(int tabIndex, {required bool isOwner}) {
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: suppliers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final m = Map<String, dynamic>.from(suppliers[i] as Map);
            final id = m['id']?.toString();
            return _SupplierCard(
              data: m,
              metrics: null,
              isOwner: isOwner,
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: brokers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final b = Map<String, dynamic>.from(brokers[i] as Map);
            final id = b['id']?.toString();
            return _BrokerCard(
              data: b,
              metrics: null,
              isOwner: isOwner,
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: cats.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final name = cats[i].toString();
            return Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: HexaColors.border)),
              child: ListTile(
                leading: const Icon(Icons.folder_outlined,
                    color: HexaColors.primaryMid),
                title: Text(name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Open items in this category'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(
                    '/contacts/category?name=${Uri.encodeComponent(name)}'),
              ),
            );
          },
        );
      default:
        final items = (d['item_names'] as List?) ?? [];
        if (items.isEmpty) {
          return Center(
              child: Text('No item name matches.',
                  style: tt.bodyMedium
                      ?.copyWith(color: HexaColors.textSecondary)));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final n = items[i].toString();
            return Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: HexaColors.border)),
              child: ListTile(
                leading: const Icon(Icons.inventory_2_outlined,
                    color: HexaColors.primaryMid),
                title: Text(n,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Item analytics'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () =>
                    context.push('/item-analytics/${Uri.encodeComponent(n)}'),
              ),
            );
          },
        );
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
      default:
        _addItemSheet();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isOwner = ref.watch(sessionProvider)?.primaryBusiness.role == 'owner';
    return Scaffold(
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          final labels = ['＋ Supplier', '＋ Broker', '＋ Category', '＋ Item'];
          return FloatingActionButton.extended(
            onPressed: _addForCurrentTab,
            icon: const Icon(Icons.add_rounded),
            label: Text(labels[_tabController.index.clamp(0, 3)]),
            backgroundColor: HexaColors.primaryMid,
            foregroundColor: Colors.white,
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Catalog',
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              'Suppliers · brokers · categories · items — pick when adding a purchase',
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
        actions: const [
          AppSettingsAction(),
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
                  _tabWithBadge('Items', _searchCountForTab(3)),
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
                hintText: 'Search suppliers, items, categories…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          _scheduleSearch('');
                        },
                      )
                    : null,
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
                          _searchResultsForTab(0, isOwner: isOwner),
                          _searchResultsForTab(1, isOwner: isOwner),
                          _searchResultsForTab(2, isOwner: isOwner),
                          _searchResultsForTab(3, isOwner: isOwner),
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
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(contactsSuppliersEnrichedProvider);
    final session = ref.watch(sessionProvider);
    final isOwner = session?.primaryBusiness.role == 'owner';
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
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
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
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
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final s = list[i];
              final id = s['id']?.toString();
              final m = s['_metrics'] as Map<String, dynamic>?;
              return _SupplierCard(
                data: Map<String, dynamic>.from(s),
                metrics: m,
                isOwner: isOwner,
                onOpen:
                    id == null ? () {} : () => context.push('/supplier/$id'),
                onDial: onDial,
                onWhatsApp: onWhatsApp,
                onEdit: () => onEdit(s),
                onDelete: () => onDelete(s),
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
      error: (_, __) => FriendlyLoadError(
        onRetry: () => ref.invalidate(contactsBrokersEnrichedProvider),
      ),
      data: (list) {
        if (list.isEmpty) return const Center(child: Text('No brokers yet'));
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(contactsBrokersEnrichedProvider);
            await ref.read(contactsBrokersEnrichedProvider.future);
          },
          child: ListView.separated(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final b = list[i];
              final id = b['id']?.toString();
              final m = b['_metrics'] as Map<String, dynamic>?;
              return _BrokerCard(
                data: Map<String, dynamic>.from(b),
                metrics: m,
                isOwner: isOwner,
                onOpen: id == null ? () {} : () => context.push('/broker/$id'),
                onEdit: () => onEdit(b),
                onDelete: () => onDelete(b),
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
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => FriendlyLoadError(
        onRetry: () {
          ref.invalidate(itemCategoriesListProvider);
          ref.invalidate(catalogItemsListProvider);
        },
      ),
      data: (cats) {
        return itemsAsync.when(
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
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No categories yet. Use ＋ Category to add one — same list as Settings → Item catalog.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              );
            }
            return ListView.separated(
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No catalog items yet. Use ＋ Item or Settings → Item catalog.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              );
            }
            return ListView.separated(
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
