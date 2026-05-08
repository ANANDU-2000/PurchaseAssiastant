import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import 'purchase_scan_draft_map_provider.dart';
import 'scan_draft_summary_sections.dart';
import 'scan_draft_table_widgets.dart';
import 'scan_draft_edit_item_sheet.dart';
import 'scan_purchase_draft_logic.dart';

/// Five-step review after AI scan (supplier → terms → items → financial note → validate/create).
class PurchaseScanDraftWizardPage extends ConsumerStatefulWidget {
  const PurchaseScanDraftWizardPage({super.key});

  @override
  ConsumerState<PurchaseScanDraftWizardPage> createState() =>
      _PurchaseScanDraftWizardPageState();
}

class _PurchaseScanDraftWizardPageState extends ConsumerState<PurchaseScanDraftWizardPage> {
  late PageController _page;
  int _step = 0;
  Map<String, dynamic>? _draft;
  bool _creating = false;

  static const _titles = [
    'Supplier & broker',
    'Terms & charges',
    'Items',
    'Financial summary',
    'Validate & create',
  ];

  @override
  void initState() {
    super.initState();
    _page = PageController();
    final snap = ref.read(purchaseScanDraftMapProvider);
    _draft = snap != null ? Map<String, dynamic>.from(snap) : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_draft == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No scan data. Go back and scan again.')),
        );
        context.pop();
      }
    });
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _applyCandidate(String key, Map<String, dynamic> cand) {
    final s = _draft;
    if (s == null) return;
    final m0 = s[key];
    if (m0 is! Map) return;
    final next = Map<String, dynamic>.from(m0);
    final id = cand['id']?.toString();
    final name = (cand['name'] ?? '').toString().trim();
    if (id != null && id.trim().isNotEmpty) next['matched_id'] = id;
    if (name.isNotEmpty) next['matched_name'] = name;
    next['confidence'] = 0.99;
    s[key] = next;
    final merged = Map<String, dynamic>.from(s);
    ref.read(purchaseScanDraftMapProvider.notifier).setDraft(merged);
    setState(() => _draft = merged);
  }

  bool get _scanIssueBlocker {
    final w = _draft?['warnings'];
    if (w is! List) return false;
    for (final e in w) {
      if (e is Map && e['severity']?.toString().toLowerCase() == 'block') return true;
    }
    return false;
  }

  Future<void> _createPurchase() async {
    final d = _draft;
    if (d == null) return;
    setState(() => _creating = true);
    try {
      final ok = await confirmScanDraftPurchase(
        ref: ref,
        context: context,
        scan: d,
        scanIssueBlocker: _scanIssueBlocker,
      );
      if (ok && mounted) {
        ref.read(purchaseScanDraftMapProvider.notifier).clear();
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Widget _billMetaCard() {
    final s = _draft!;
    final inv = s['invoice_number']?.toString().trim();
    final bd = s['bill_date']?.toString().trim();
    if ((inv == null || inv.isEmpty) && (bd == null || bd.isEmpty)) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Bill details', style: HexaDsType.formSectionLabel),
            if (inv != null && inv.isNotEmpty) Text('Invoice: $inv', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (bd != null && bd.isNotEmpty) Text('Bill date: $bd', style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _financialStep() {
    final s = _draft!;
    final items = s['items'];
    double roughLineSum = 0;
    var counted = 0;
    if (items is List) {
      for (final e in items) {
        if (e is! Map) continue;
        final lt = e['line_total'] ?? e['preview_line_total'];
        final v = lt is num ? lt.toDouble() : double.tryParse(lt?.toString() ?? '');
        if (v != null && v > 0) {
          roughLineSum += v;
          counted++;
        }
      }
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Financial summary', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'Authoritative totals, bags, kg, freight, margin, and duplicate checks run on the server '
          'when you create the purchase. Numbers below are informational only.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 16),
        if (counted > 0)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Sum of line totals (from scan): ₹${roughLineSum.toStringAsFixed(0)} ($counted lines)',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        const SizedBox(height: 12),
        scanDraftChargesCard(s),
      ],
    );
  }

  Widget _validationStep() {
    final ready = scanDraftReadyForCreate(_draft, scanIssueBlocker: _scanIssueBlocker);
    final issues = <String>[];
    if (_draft == null) {
      issues.add('Missing draft');
    } else {
      if (_scanIssueBlocker) issues.add('Blocking warnings on scan — fix or retake.');
      final sup = _draft!['supplier'];
      final hasSup = sup is Map && (sup['matched_id']?.toString().trim().isNotEmpty ?? false);
      if (!hasSup) issues.add('Match supplier');
      final items = _draft!['items'];
      if (items is! List || items.whereType<Map>().isEmpty) {
        issues.add('Need at least one item');
      } else {
        for (var i = 0; i < items.length; i++) {
          final it = items[i];
          if (it is! Map) continue;
          final m = (it['matched_catalog_item_id'] ?? it['matched_id'])?.toString().trim();
          final r = double.tryParse(it['purchase_rate']?.toString() ?? '');
          if (m == null || m.isEmpty) issues.add('Row ${i + 1}: match catalog item');
          if (r == null || r <= 0) issues.add('Row ${i + 1}: purchase rate');
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Final validation', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (issues.isEmpty)
          const Card(
            color: Color(0xFFECFDF5),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Ready to create. Server will still enforce duplicates and validations.',
                style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF065F46)),
              ),
            ),
          )
        else
          Card(
            color: const Color(0xFFFFFBEB),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Fix before creating:', style: TextStyle(fontWeight: FontWeight.w900)),
                  for (final x in issues) Text('• $x'),
                ],
              ),
            ),
          ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: (!_creating && ready) ? _createPurchase : null,
          icon: _creating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_circle_rounded),
          label: Text(_creating ? 'Creating…' : 'Create purchase'),
          style: FilledButton.styleFrom(backgroundColor: HexaColors.brandPrimary),
        ),
      ],
    );
  }

  Widget _itemsStep() {
    final s = _draft!;
    final items = s['items'];
    if (items is! List || items.isEmpty) {
      return const Center(child: Text('No items in scan.'));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Item matching', style: HexaDsType.formSectionLabel),
        const SizedBox(height: 4),
        const Text(
          'Tap a row to edit. Expand for kg / raw name. Match catalog items before the last step.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ScanDraftTableHeader(),
                const SizedBox(height: 6),
                for (var i = 0; i < items.length; i++)
                  if (items[i] is Map)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ScanDraftExpandableItemRow(
                        item: Map<String, dynamic>.from(items[i] as Map),
                        onEdit: () async {
                          await editScanDraftItemRow(
                            context,
                            index: i,
                            item: Map<String, dynamic>.from(items[i] as Map),
                            onSaved: (idx, next) {
                              final list = _draft!['items'];
                              if (list is List && idx >= 0 && idx < list.length) {
                                list[idx] = next;
                                ref.read(purchaseScanDraftMapProvider.notifier).setDraft(_draft!);
                                setState(() => _draft = Map<String, dynamic>.from(_draft!));
                              }
                            },
                          );
                        },
                        trailing: scanDraftConfChip((items[i] as Map)['confidence']),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    if (d == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Purchase draft (${_step + 1}/5)'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _titles[_step],
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(value: (_step + 1) / 5),
          Expanded(
            child: PageView(
              controller: _page,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _step = i),
              children: [
                ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    scanDraftSupplierBrokerCard(scan: d, onPickCandidate: _applyCandidate),
                    _billMetaCard(),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    scanDraftChargesCard(d),
                    const SizedBox(height: 12),
                    scanDraftWarningsCard(d),
                  ],
                ),
                _itemsStep(),
                _financialStep(),
                _validationStep(),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  if (_step > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _creating
                            ? null
                            : () {
                                _page.previousPage(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOutCubic,
                                );
                              },
                        child: const Text('Back'),
                      ),
                    ),
                  if (_step > 0 && _step < 4) const SizedBox(width: 8),
                  if (_step < 4)
                    Expanded(
                      child: FilledButton(
                        onPressed: _creating
                            ? null
                            : () {
                                HapticFeedback.selectionClick();
                                _page.nextPage(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOutCubic,
                                );
                              },
                        child: const Text('Next'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
