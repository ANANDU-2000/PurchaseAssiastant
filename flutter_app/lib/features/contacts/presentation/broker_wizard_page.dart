import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/contacts_hub_provider.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../shared/widgets/full_screen_form_scaffold.dart';
import 'supplier_create_wizard_page.dart';

class BrokerWizardPage extends ConsumerStatefulWidget {
  const BrokerWizardPage({super.key, this.brokerId});

  final String? brokerId;

  @override
  ConsumerState<BrokerWizardPage> createState() => _BrokerWizardPageState();
}

class _BrokerWizardPageState extends ConsumerState<BrokerWizardPage> {
  int _step = 0;
  bool _dirty = false;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _wa = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();
  final _commission = TextEditingController();
  final _searchSuppliers = TextEditingController();
  final _searchItems = TextEditingController();

  String _commissionType = 'percent';
  final Set<String> _supplierIds = {};
  final Set<String> _categoryIds = {};
  final Set<String> _typeIds = {};
  final Set<String> _itemIds = {};
  final Map<String, String> _itemLabels = {};
  String? _nameError;

  List<Map<String, dynamic>> _brokerRows = [];
  String? _dupHint;
  Timer? _dupTimer;
  Timer? _itemDebounce;
  List<Map<String, dynamic>> _itemHits = [];

  @override
  void initState() {
    super.initState();
    _phone.addListener(_syncWa);
    _name.addListener(_checkDupDebounced);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadInitial());
    });
  }

  @override
  void dispose() {
    _dupTimer?.cancel();
    _itemDebounce?.cancel();
    _name.dispose();
    _phone.dispose();
    _wa.dispose();
    _location.dispose();
    _notes.dispose();
    _commission.dispose();
    _searchSuppliers.dispose();
    _searchItems.dispose();
    super.dispose();
  }

  void _syncWa() {
    final p = _phone.text.replaceAll(RegExp(r'\D'), '');
    final w = _wa.text.replaceAll(RegExp(r'\D'), '');
    if (w.isEmpty || w == p) _wa.text = _phone.text;
  }

  Future<void> _loadInitial() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      _brokerRows =
          await ref.read(hexaApiProvider).listBrokers(businessId: session.primaryBusiness.id);
    } catch (_) {}
    if (widget.brokerId != null && widget.brokerId!.isNotEmpty) {
      try {
        final b = await ref.read(hexaApiProvider).getBroker(
              businessId: session.primaryBusiness.id,
              brokerId: widget.brokerId!,
            );
        if (!mounted || b.isEmpty) return;
        setState(() {
          _name.text = b['name']?.toString() ?? '';
          _phone.text = b['phone']?.toString() ?? '';
          _wa.text = b['whatsapp_number']?.toString() ?? '';
          _location.text = b['location']?.toString() ?? '';
          _notes.text = b['notes']?.toString() ?? '';
          _commissionType = b['commission_type']?.toString() == 'flat' ? 'flat' : 'percent';
          _commission.text = b['commission_value']?.toString() ?? '';
          _supplierIds
            ..clear()
            ..addAll(((b['supplier_ids'] as List?) ?? const [])
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty));
          final pj = b['preferences_json']?.toString();
          if (pj != null && pj.trim().isNotEmpty) {
            final p = jsonDecode(pj) as Map<String, dynamic>;
            _categoryIds
              ..clear()
              ..addAll((p['category_ids'] as List? ?? const []).map((e) => e.toString()));
            _typeIds
              ..clear()
              ..addAll((p['type_ids'] as List? ?? const []).map((e) => e.toString()));
            _itemIds
              ..clear()
              ..addAll((p['item_ids'] as List? ?? const []).map((e) => e.toString()));
          }
          _dirty = false;
        });
      } catch (_) {}
    }
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _checkDupDebounced() {
    _dupTimer?.cancel();
    _dupTimer = Timer(const Duration(milliseconds: 350), () {
      final n = _name.text.trim().toLowerCase();
      if (n.length < 2) {
        if (mounted) setState(() => _dupHint = null);
        return;
      }
      final hit = _brokerRows.where((b) {
        final id = b['id']?.toString();
        if (widget.brokerId != null && id == widget.brokerId) return false;
        final bn = (b['name']?.toString() ?? '').toLowerCase();
        return bn == n || bn.contains(n) || n.contains(bn);
      }).firstOrNull;
      if (!mounted) return;
      setState(() {
        _dupHint = hit == null ? null : 'Similar broker exists: ${hit['name']}';
      });
    });
  }

  bool _validateStep0() {
    _nameError = null;
    if (_name.text.trim().isEmpty) _nameError = 'Required';
    setState(() {});
    return _nameError == null;
  }

  Future<void> _runItemSearch(String q) async {
    _itemDebounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _itemHits = []);
      return;
    }
    _itemDebounce = Timer(const Duration(milliseconds: 300), () async {
      final session = ref.read(sessionProvider);
      if (session == null) return;
      try {
        final res = await ref.read(hexaApiProvider).unifiedSearch(
              businessId: session.primaryBusiness.id,
              q: q.trim(),
            );
        final items = res['catalog_items'];
        final out = <Map<String, dynamic>>[];
        if (items is List) {
          for (final e in items.take(20)) {
            if (e is Map) out.add(Map<String, dynamic>.from(e));
          }
        }
        if (mounted) setState(() => _itemHits = out);
      } catch (_) {
        if (mounted) setState(() => _itemHits = []);
      }
    });
  }

  Future<void> _save() async {
    if (!_validateStep0()) {
      setState(() => _step = 0);
      return;
    }
    if (widget.brokerId == null && _dupHint != null && mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Similar broker'),
          content: Text('$_dupHint\n\nContinue saving this broker?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Go back')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
          ],
        ),
      );
      if (go != true) return;
    }
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final bid = session.primaryBusiness.id;
    final cv = double.tryParse(_commission.text.trim());
    final prefs = <String, dynamic>{
      'category_ids': _categoryIds.toList(),
      'type_ids': _typeIds.toList(),
      'item_ids': _itemIds.toList(),
    };
    try {
      Map<String, dynamic> out;
      if (widget.brokerId != null && widget.brokerId!.isNotEmpty) {
        out = await ref.read(hexaApiProvider).updateBroker(
              businessId: bid,
              brokerId: widget.brokerId!,
              name: _name.text.trim(),
              phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
              whatsappNumber: _wa.text.trim().isEmpty ? null : _wa.text.trim(),
              location: _location.text.trim().isEmpty ? null : _location.text.trim(),
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              commissionType: _commissionType,
              commissionValue: cv,
              supplierIds: _supplierIds.toList(),
              preferences: prefs,
            );
      } else {
        out = await ref.read(hexaApiProvider).createBroker(
              businessId: bid,
              name: _name.text.trim(),
              phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
              whatsappNumber: _wa.text.trim().isEmpty ? null : _wa.text.trim(),
              location: _location.text.trim().isEmpty ? null : _location.text.trim(),
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              commissionType: _commissionType,
              commissionValue: cv,
              supplierIds: _supplierIds.toList(),
              preferences: prefs,
            );
      }
      final brokerId = out['id']?.toString();
      if (brokerId != null && brokerId.isNotEmpty) {
        final allSup = await ref.read(suppliersListProvider.future);
        for (final e in allSup) {
          final s = Map<String, dynamic>.from(e as Map);
          final sid = s['id']?.toString();
          if (sid == null || sid.isEmpty) continue;
          final existing = ((s['broker_ids'] as List?) ?? const [])
              .map((x) => x.toString())
              .toList();
          final shouldHave = _supplierIds.contains(sid);
          final has = existing.contains(brokerId);
          if (shouldHave && !has) {
            existing.add(brokerId);
          } else if (!shouldHave && has) {
            existing.removeWhere((x) => x == brokerId);
          } else {
            continue;
          }
          await ref.read(hexaApiProvider).updateSupplier(
                businessId: bid,
                supplierId: sid,
                brokerIds: existing,
                brokerId: existing.isEmpty ? null : existing.first,
              );
        }
      }
      ref.invalidate(brokersListProvider);
      ref.invalidate(contactsBrokersEnrichedProvider);
      ref.invalidate(suppliersListProvider);
      ref.invalidate(contactsSuppliersEnrichedProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.brokerId == null ? 'Broker created' : 'Broker updated'),
        ),
      );
      context.pop();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
    }
  }

  Future<void> _exit() async {
    if (!_dirty || !mounted) {
      if (mounted) context.pop();
      return;
    }
    final keep = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save changes?'),
        content: const Text('You have unsaved broker changes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stay')),
        ],
      ),
    );
    if (keep == false && mounted) context.pop();
  }

  InputDecoration _d(String label, {String? hint}) => InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );

  Widget _step0() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      children: [
        if (_dupHint != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_dupHint!, style: const TextStyle(color: Colors.orange)),
          ),
        TextField(
          controller: _name,
          decoration: _d('Broker Name *').copyWith(errorText: _nameError),
          onChanged: (_) => _markDirty(),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _phone,
          decoration: _d('Phone *'),
          keyboardType: TextInputType.phone,
          onChanged: (_) => _markDirty(),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _wa,
          decoration: _d('WhatsApp'),
          keyboardType: TextInputType.phone,
          onChanged: (_) => _markDirty(),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _location,
          decoration: _d('Location'),
          onChanged: (_) => _markDirty(),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notes,
          decoration: _d('Notes'),
          minLines: 2,
          maxLines: 3,
          onChanged: (_) => _markDirty(),
        ),
      ],
    );
  }

  Widget _step1() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'percent', label: Text('Percentage %')),
            ButtonSegment(value: 'flat', label: Text('Fixed ₹')),
          ],
          selected: {_commissionType},
          onSelectionChanged: (v) {
            setState(() {
              _commissionType = v.first;
              _markDirty();
            });
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _commission,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _d(_commissionType == 'percent'
              ? 'Commission Value (%)'
              : 'Commission Value (₹)'),
          onChanged: (_) => _markDirty(),
        ),
      ],
    );
  }

  Widget _step2() {
    final suppliersAsync = ref.watch(suppliersListProvider);
    final q = _searchSuppliers.text.trim().toLowerCase();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchSuppliers,
                decoration: _d('Search suppliers'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SupplierCreateWizardPage(),
                  fullscreenDialog: true,
                ),
              ),
              child: const Text('Create Supplier'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        suppliersAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('Could not load suppliers'),
          data: (rows) {
            final filtered = rows
                .map((e) => Map<String, dynamic>.from(e as Map))
                .where((s) =>
                    q.isEmpty || (s['name']?.toString().toLowerCase().contains(q) ?? false))
                .toList();
            return Column(
              children: filtered.map((s) {
                final sid = s['id']?.toString() ?? '';
                final checked = _supplierIds.contains(sid);
                return CheckboxListTile(
                  dense: true,
                  value: checked,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _supplierIds.add(sid);
                      } else {
                        _supplierIds.remove(sid);
                      }
                      _markDirty();
                    });
                  },
                  title: Text(s['name']?.toString() ?? ''),
                  subtitle: Text(s['location']?.toString() ?? ''),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _step3() {
    final cats = ref.watch(itemCategoriesListProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      children: [
        TextField(
          controller: _searchItems,
          decoration: _d('Search items / categories'),
          onChanged: (v) => _runItemSearch(v),
        ),
        const SizedBox(height: 8),
        cats.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const SizedBox.shrink(),
          data: (rows) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: rows.map((c) {
              final id = c['id']?.toString() ?? '';
              final sel = _categoryIds.contains(id);
              return FilterChip(
                label: Text(c['name']?.toString() ?? ''),
                selected: sel,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _categoryIds.add(id);
                    } else {
                      _categoryIds.remove(id);
                    }
                    _markDirty();
                  });
                },
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),
        ..._itemHits.map((h) {
          final id = h['id']?.toString();
          if (id == null || id.isEmpty) return const SizedBox.shrink();
          final name = h['name']?.toString() ?? h['item_name']?.toString() ?? 'Item';
          final selected = _itemIds.contains(id);
          return ListTile(
            dense: true,
            title: Text(name),
            subtitle: Text(h['category']?.toString() ?? ''),
            trailing:
                Icon(selected ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded),
            onTap: () {
              setState(() {
                if (selected) {
                  _itemIds.remove(id);
                } else {
                  _itemIds.add(id);
                }
                _itemLabels[id] = name;
                _markDirty();
              });
            },
          );
        }),
      ],
    );
  }

  Widget _step4() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      children: [
        _reviewCard('Basic Info', [
          _kv('Name', _name.text.trim().isEmpty ? '—' : _name.text.trim()),
          _kv('Phone', _phone.text.trim().isEmpty ? '—' : _phone.text.trim()),
          _kv('WhatsApp', _wa.text.trim().isEmpty ? '—' : _wa.text.trim()),
          _kv('Location', _location.text.trim().isEmpty ? '—' : _location.text.trim()),
        ]),
        _reviewCard('Commission', [
          _kv('Type', _commissionType == 'percent' ? 'Percentage %' : 'Fixed ₹'),
          _kv('Value', _commission.text.trim().isEmpty ? '—' : _commission.text.trim()),
        ]),
        _reviewCard('Connections', [
          _kv('Suppliers linked', '${_supplierIds.length}'),
          _kv('Items linked', '${_itemIds.length}'),
          _kv('Categories linked', '${_categoryIds.length}'),
        ]),
      ],
    );
  }

  Widget _reviewCard(String title, List<Widget> rows) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        ...rows,
      ]),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              k,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_step) {
      case 0:
        return _step0();
      case 1:
        return _step1();
      case 2:
        return _step2();
      case 3:
        return _step3();
      default:
        return _step4();
    }
  }

  Widget _footer() {
    final finalStep = _step == 4;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          TextButton(
            onPressed: _exit,
            child: Text(finalStep ? 'Cancel' : 'Cancel'),
          ),
          const Spacer(),
          if (finalStep)
            FilledButton(
              onPressed: _save,
              child: const Text('Save Broker'),
            )
          else
            FilledButton(
              onPressed: () {
                if (_step == 0 && !_validateStep0()) return;
                setState(() {
                  _step++;
                  _dirty = true;
                });
              },
              child: const Text('Next'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      'Basic Info',
      'Commission Setup',
      'Supplier Mapping',
      'Item Mapping',
      'Review',
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _exit();
      },
      child: FullScreenFormScaffold(
        title: widget.brokerId == null ? 'New broker' : 'Edit broker',
        subtitle: '${titles[_step]} · Step ${_step + 1} of ${titles.length}',
        onBackPressed: () {
          if (_step > 0) {
            setState(() => _step--);
          } else {
            unawaited(_exit());
          }
        },
        body: _body(),
        bottom: _footer(),
      ),
    );
  }
}
