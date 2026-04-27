import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/calc_engine.dart' show lineMoney;
import '../../../core/catalog/item_trade_history.dart' show tradeLineToCalc;
import '../../../core/config/app_config.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/purchase_prefill_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../shared/widgets/hexa_empty_state.dart';
import 'supplier_create_wizard_page.dart';

final _supplierProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, supplierId) async {
  final session = ref.watch(sessionProvider);
  if (session == null) throw StateError('Not signed in');
  return ref.read(hexaApiProvider).getSupplier(
        businessId: session.primaryBusiness.id,
        supplierId: supplierId,
      );
});

DateTime _dOnly(DateTime d) => DateTime(d.year, d.month, d.day);

List<TradePurchase> _tradesInDateWindow(
  List<TradePurchase> all,
  DateTime from,
  DateTime to,
) {
  return [
    for (final p in all)
      if (!_dOnly(p.purchaseDate).isBefore(from) &&
          !_dOnly(p.purchaseDate).isAfter(to))
        p,
  ];
}

double _lineAmountInr(TradePurchaseLine ln) =>
    lineMoney(tradeLineToCalc(ln));

class SupplierDetailPage extends ConsumerStatefulWidget {
  const SupplierDetailPage({super.key, required this.supplierId});

  final String supplierId;

  @override
  ConsumerState<SupplierDetailPage> createState() => _SupplierDetailPageState();
}

class _SupplierDetailPageState extends ConsumerState<SupplierDetailPage> {
  late DateTime _to;
  late DateTime _from;
  bool _loading = false;
  /// PUR bills in the selected date range (trade flow only; legacy entries removed)
  List<TradePurchase> _trades = const [];
  final _searchCtrl = TextEditingController();
  /// Matches ENTRY date chips: This Month / 3 Months / 6 Months / All
  String _dateChip = '3 Months';

  @override
  void initState() {
    super.initState();
    final n = _dOnly(DateTime.now());
    _to = n;
    _from = n.subtract(const Duration(days: 89));
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    ref.invalidate(_supplierProvider(widget.supplierId));
    setState(() => _loading = true);
    final api = ref.read(hexaApiProvider);
    try {
      var trades = <TradePurchase>[];
      final traw = await api.listTradePurchases(
        businessId: session.primaryBusiness.id,
        limit: 200,
        status: 'all',
        supplierId: widget.supplierId,
      );
      for (final row in traw) {
        try {
          trades.add(
            TradePurchase.fromJson(Map<String, dynamic>.from(row as Map)),
          );
        } catch (_) {}
      }
      trades = _tradesInDateWindow(trades, _from, _to);
      trades.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
      if (mounted) {
        setState(() {
          _trades = trades;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }

  void _applyDateChip(String label) {
    final n = _dOnly(DateTime.now());
    setState(() {
      _dateChip = label;
      _to = n;
      switch (label) {
        case 'This Month':
          _from = DateTime(n.year, n.month, 1);
        case '3 Months':
          _from = n.subtract(const Duration(days: 89));
        case '6 Months':
          _from = n.subtract(const Duration(days: 179));
        case 'All':
          _from = _dOnly(DateTime(2020));
        default:
          _from = n.subtract(const Duration(days: 89));
      }
    });
    _reload();
  }

  static bool _isActiveBill(TradePurchase p) =>
      p.statusEnum != PurchaseStatus.draft &&
      p.statusEnum != PurchaseStatus.cancelled;

  (int bills, double spend, double unpaid) _rangeStats() {
    var bills = 0, spend = 0.0, unpaid = 0.0;
    for (final p in _trades) {
      if (!_isActiveBill(p)) continue;
      bills++;
      spend += p.totalAmount;
      unpaid += p.remaining;
    }
    return (bills, spend, unpaid);
  }

  List<TradePurchase> _tradesForList() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _trades;
    return [
      for (final p in _trades)
        if (_tradeMatchesQuery(p, q)) p,
    ];
  }

  bool _tradeMatchesQuery(TradePurchase p, String q) {
    if (p.humanId.toLowerCase().contains(q)) return true;
    for (final ln in p.lines) {
      if (ln.itemName.toLowerCase().contains(q)) return true;
    }
    return false;
  }

  Future<void> _dial(String? phone) async {
    if (phone == null || phone.trim().isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'\s'), ''));
    if (await canLaunchUrl(uri)) await launchUrl(uri);
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

  Future<void> _exportCsv() async {
    final buf = StringBuffer(
        'date,pur_id,item,qty,unit,landing_per_unit,selling,total_line\n');
    for (final p in _trades) {
      final d = p.purchaseDate.toIso8601String().split('T').first;
      for (final ln in p.lines) {
        final lpu = (ln.kgPerUnit != null &&
                ln.landingCostPerKg != null &&
                (ln.kgPerUnit ?? 0) > 0)
            ? ln.landingCostPerKg
            : ln.landingCost;
        buf.writeln(
            '$d,${p.humanId},"${ln.itemName.replaceAll('"', "'")}",${ln.qty},${ln.unit},$lpu,${ln.sellingCost ?? ''},${_lineAmountInr(ln)}');
      }
    }
    if (buf.length < 100) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No trade lines to export in this range.')),
        );
      }
      return;
    }
    await Share.share(buf.toString(),
        subject: '${AppConfig.appName} supplier export');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_supplierProvider(widget.supplierId));
    final tt = Theme.of(context).textTheme;
    final fmt = DateFormat.yMMMd();

    const teal = Color(0xFF17A8A7);
    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      floatingActionButton: async.maybeWhen(
        data: (_) => FloatingActionButton.extended(
          onPressed: () {
            ref.read(pendingPurchaseSupplierIdProvider.notifier).state =
                widget.supplierId;
            context.pushNamed('purchase_new');
          },
          backgroundColor: teal,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_shopping_cart_rounded),
          label: const Text('New purchase'),
        ),
        orElse: () => null,
      ),
      appBar: AppBar(
        backgroundColor: HexaColors.brandBackground,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.popOrGo('/contacts')),
        title: async.maybeWhen(
          data: (s) => Text(
            s['name']?.toString() ?? 'Supplier',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          orElse: () => const Text('Supplier'),
        ),
        actions: [
          async.maybeWhen(
            data: (_) => IconButton(
              tooltip: 'Edit supplier',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        SupplierCreateWizardPage(supplierId: widget.supplierId),
                  ),
                );
              },
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          IconButton(
            tooltip: 'Statement & ledger',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () =>
                context.push('/supplier/${widget.supplierId}/ledger'),
          ),
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _trades.isEmpty ? null : _exportCsv,
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => FriendlyLoadError(
          message: 'Could not load supplier',
          onRetry: () => ref.invalidate(_supplierProvider(widget.supplierId)),
        ),
        data: (s) {
          final phone = s['phone']?.toString();
          final wa = s['whatsapp_number']?.toString();
          final bid = s['broker_id']?.toString();
          final loc = s['location']?.toString() ?? '';
          final name = s['name']?.toString() ?? 'n/a';
          final gst = s['gst_number']?.toString() ?? s['gstin']?.toString() ?? '';
          final cs = Theme.of(context).colorScheme;
          final st = _rangeStats();
          final billN = st.$1;
          final spendN = st.$2;
          final unpaidN = st.$3;
          final inr = NumberFormat.currency(
            locale: 'en_IN',
            symbol: '₹',
            decimalDigits: 0,
          );
          final shown = _tradesForList();
          const chipTeal = Color(0xFF17A8A7);
          const chipText = Color(0xFF374151);
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
              children: [
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: tt.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        ),
                        if (loc.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.location_on_outlined,
                                  size: 14, color: cs.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  loc,
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (phone != null && phone.isNotEmpty)
                              InkWell(
                                onTap: () => _dial(phone),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: chipTeal.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.phone,
                                          size: 14, color: chipTeal),
                                      const SizedBox(width: 4),
                                      Text(
                                        phone,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: chipTeal,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (wa != null && wa.isNotEmpty)
                              InkWell(
                                onTap: () => _openWhatsApp(wa),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.message,
                                          size: 14,
                                          color: Colors.green.shade700),
                                      const SizedBox(width: 4),
                                      Text(
                                        'WhatsApp',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (gst.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'GSTIN: $gst',
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _QuickStat(
                              label: 'Bills',
                              value: '$billN',
                            ),
                            _SupplierVBar(cs: cs),
                            _QuickStat(
                              label: 'Total spend',
                              value: inr.format(spendN.round()),
                            ),
                            _SupplierVBar(cs: cs),
                            _QuickStat(
                              label: 'Unpaid',
                              value: inr.format(unpaidN.round()),
                              valueColor: unpaidN > 0
                                  ? Colors.orange.shade800
                                  : Colors.green.shade800,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (bid != null) ...[
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.handshake_outlined),
                    title: const Text('Linked broker'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/broker/$bid'),
                  ),
                ],
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final label in <String>[
                        'This Month',
                        '3 Months',
                        '6 Months',
                        'All',
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: _dateChip == label
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: _dateChip == label
                                    ? Colors.white
                                    : chipText,
                              ),
                            ),
                            selected: _dateChip == label,
                            onSelected: (_) => _applyDateChip(label),
                            selectedColor: chipTeal,
                            backgroundColor: cs.surfaceContainerHighest
                                .withValues(alpha: 0.6),
                            side: BorderSide.none,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${fmt.format(_from)} – ${fmt.format(_to)}',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search by invoice, item…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 12),
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Purchase history',
                        style: tt.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        shown.isEmpty
                            ? '0 bills'
                            : '${shown.length} bill${shown.length == 1 ? '' : 's'}',
                        style: tt.labelSmall
                            ?.copyWith(color: HexaColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (shown.isEmpty)
                    HexaEmptyState(
                      icon: Icons.receipt_long_rounded,
                      title: 'No trade purchases in this view',
                      subtitle:
                          'Change the date range, clear search, or add a purchase.',
                      primaryActionLabel: 'Add purchase',
                      onPrimaryAction: () => context.push('/purchase/new'),
                    )
                  else
                    _SupplierTradeTable(trades: shown),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.receipt_long_outlined,
                        size: 20, color: cs.primary),
                    title: Text(
                      'Full PUR ledger & statement',
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () =>
                        context.push('/supplier/${widget.supplierId}/ledger'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _QuickStat extends StatelessWidget {
  const _QuickStat({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: valueColor ?? const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SupplierVBar extends StatelessWidget {
  const _SupplierVBar({required this.cs});

  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: cs.outlineVariant.withValues(alpha: 0.5),
    );
  }
}

class _SupplierTradeTable extends StatelessWidget {
  const _SupplierTradeTable({required this.trades});

  final List<TradePurchase> trades;

  String _inr(num v) => NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 0,
      ).format(v);

  String _rateL(TradePurchaseLine ln) {
    final kpu = ln.kgPerUnit;
    final lcpk = ln.landingCostPerKg;
    if (kpu != null && lcpk != null && kpu > 0 && lcpk > 0) {
      return 'L ${_inr(lcpk)}/kg';
    }
    return 'L ${_inr(ln.landingCost)}/${ln.unit}';
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: trades.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 12, endIndent: 12),
        itemBuilder: (context, ip) {
          final p = trades[ip];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  p.humanId,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${DateFormat.yMMMd().format(p.purchaseDate)} · ${p.derivedStatus}'
                  '${(p.brokerName ?? '').isNotEmpty ? ' · ${p.brokerName}' : ''}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                trailing: Text(
                  _inr(p.totalAmount.round()),
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                onTap: () => context.push('/purchase/detail/${p.id}'),
              ),
              if (p.lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'No line items',
                    style: tt.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Column(
                    children: [
                      for (final ln in p.lines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  ln.itemName,
                                  style: tt.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${ln.qty % 1 == 0 ? ln.qty.toInt() : ln.qty.toStringAsFixed(1)} ${ln.unit}',
                                  textAlign: TextAlign.right,
                                  style: tt.labelSmall,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _rateL(ln),
                                  textAlign: TextAlign.right,
                                  style: tt.labelSmall
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ),
                              if (ln.sellingCost != null) ...[
                                const SizedBox(width: 4),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'S ${_inr(ln.sellingCost!)}',
                                    textAlign: TextAlign.right,
                                    style: tt.labelSmall
                                        ?.copyWith(color: cs.onSurfaceVariant),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 4),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _inr(_lineAmountInr(ln).round()),
                                  textAlign: TextAlign.right,
                                  style: tt.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
