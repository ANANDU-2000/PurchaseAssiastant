import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/business_write_revision.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../shared/widgets/hexa_empty_state.dart';

enum TradeLedgerKind { supplier, broker }

/// PUR ledger for one supplier or one broker (trade purchases only).
class TradeLedgerPage extends ConsumerStatefulWidget {
  const TradeLedgerPage({
    super.key,
    required this.kind,
    required this.entityId,
  });

  final TradeLedgerKind kind;
  final String entityId;

  @override
  ConsumerState<TradeLedgerPage> createState() => _TradeLedgerPageState();
}

class _TradeLedgerPageState extends ConsumerState<TradeLedgerPage> {
  bool _loading = true;
  String? _error;
  List<TradePurchase> _rows = const [];

  String get _title => widget.kind == TradeLedgerKind.supplier
      ? 'Supplier ledger'
      : 'Broker ledger';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = ref.read(sessionProvider);
    if (session == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ref.read(hexaApiProvider).listTradePurchases(
            businessId: session.primaryBusiness.id,
            limit: 200,
            status: 'all',
            supplierId:
                widget.kind == TradeLedgerKind.supplier ? widget.entityId : null,
            brokerId:
                widget.kind == TradeLedgerKind.broker ? widget.entityId : null,
          );
      if (!mounted) return;
      final parsed = <TradePurchase>[];
      for (final e in raw) {
        try {
          parsed.add(
            TradePurchase.fromJson(Map<String, dynamic>.from(e as Map)),
          );
        } catch (_) {}
      }
      parsed.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
      setState(() {
        _rows = parsed;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  static String _inr(num n) =>
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
          .format(n);

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(businessDataWriteRevisionProvider, (prev, next) {
      if (prev != null && next > prev && mounted) {
        _load();
      }
    });

    final sumTotal = _rows.fold<double>(0, (s, p) => s + p.totalAmount);
    final sumDue = _rows.fold<double>(0, (s, p) => s + p.remaining);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Summary',
                                style: tt.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${_rows.length} purchase(s) · Bill total ${_inr(sumTotal.round())}',
                                style: tt.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Outstanding (unpaid balance) ${_inr(sumDue.round())}',
                                style: tt.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: sumDue > 1
                                      ? HexaColors.warning
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_rows.isEmpty)
                        HexaEmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No trade purchases yet',
                          subtitle: widget.kind == TradeLedgerKind.supplier
                              ? 'Record a purchase with this supplier as the party to see it here.'
                              : 'Record a purchase with this broker attached to see it here.',
                          primaryActionLabel: 'New purchase',
                          onPrimaryAction: () => context.push('/purchase/new'),
                        )
                      else
                        ..._rows.map((p) {
                          final st = p.statusEnum;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(
                                p.humanId,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                '${DateFormat.yMMMd().format(p.purchaseDate)} · ${p.itemsSummary.isEmpty ? '${p.lines.length} line(s)' : p.itemsSummary}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _inr(p.totalAmount.round()),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    st.label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: st.color,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () =>
                                  context.push('/purchase/detail/${p.id}'),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}
