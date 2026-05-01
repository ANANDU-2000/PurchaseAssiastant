import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/calc_engine.dart';
import '../../../core/models/business_profile.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/analytics_kpi_provider.dart'
    show analyticsDateRangeProvider;
import '../../../core/providers/business_aggregates_invalidation.dart'
    show invalidatePurchaseWorkspace;
import '../../../core/providers/business_profile_provider.dart'
    show invoiceBusinessProfileProvider;
import '../../../core/services/pdf_text_safe.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/trade_purchase_commission.dart'
    show tradePurchaseCommissionInr;
import '../../../core/utils/unit_classifier.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../../shared/widgets/shell_quick_ref_actions.dart';
import 'analytics_report_helpers.dart' show analyticsCsvCell;

/// Each trade line is assigned to **at most one** Smart Report bucket (no unit mixing).
///
/// Bag: [UnitType.weightBag] **and** bag/sack wire unit.  
/// Box: box wire, [UnitType.multiPackBox], or [UnitType.singlePack] with box wire.  
/// Tin: tin wire, or [UnitType.singlePack] with tin wire.
DateTime _dOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool _inInclusiveRange(DateTime purchaseDate, DateTime from, DateTime to) {
  final pd = _dOnly(purchaseDate);
  final a = _dOnly(from);
  final b = _dOnly(to);
  return !pd.isBefore(a) && !pd.isAfter(b);
}

enum _PackKind { bag, box, tin }

enum _MainTab { items, suppliers, brokers }

enum _ItemsSubTab { bag, box, tin }

Future<List<TradePurchase>> _fetchPurchases(Ref ref) async {
  final session = ref.watch(sessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return [];
  final api = ref.read(hexaApiProvider);
  const limit = 500;
  final out = <TradePurchase>[];
  final seenIds = <String>{};

  for (var offset = 0; offset < 50000; offset += limit) {
    final raw = await api.listTradePurchases(
      businessId: session.primaryBusiness.id,
      limit: limit,
      offset: offset,
      status: 'all',
    );
    if (raw.isEmpty) break;
    for (final e in raw) {
      try {
        final p = TradePurchase.fromJson(Map<String, dynamic>.from(e as Map));
        if (p.id.isEmpty) continue;
        if (!_inInclusiveRange(p.purchaseDate, range.from, range.to)) continue;
        if (seenIds.add(p.id)) out.add(p);
      } catch (_) {}
    }
    if (raw.length < limit) break;
  }
  return out;
}

final smartReportPurchasesProvider =
    FutureProvider.autoDispose<List<TradePurchase>>((ref) => _fetchPurchases(ref));

_PackKind? _routeLineBucket(TradePurchaseLine l) {
  final clf = UnitClassifier.classify(
    itemName: l.itemName,
    lineUnit: l.unit,
    catalogDefaultUnit: l.defaultPurchaseUnit ?? l.defaultUnit,
    catalogDefaultKgPerBag: l.defaultKgPerBag,
  );
  final u = l.unit.trim().toLowerCase();
  final up = l.unit.trim().toUpperCase();
  final looksBag = u == 'bag' || u == 'sack' || up.contains('BAG') || up.contains('SACK');
  if (clf.type == UnitType.weightBag && looksBag) return _PackKind.bag;

  final looksBox =
      u == 'box' || up.contains('BOX') || (clf.type == UnitType.singlePack && u == 'box');
  if (clf.type == UnitType.multiPackBox || looksBox) return _PackKind.box;

  final looksTin =
      u == 'tin' || up.contains('TIN') || (clf.type == UnitType.singlePack && u == 'tin');
  if (looksTin) return _PackKind.tin;

  return null;
}

double _kgLine(TradePurchaseLine l) => ledgerTradeLineWeightKg(
      itemName: l.itemName,
      unit: l.unit,
      qty: l.qty,
      catalogDefaultUnit: l.defaultPurchaseUnit ?? l.defaultUnit,
      catalogDefaultKgPerBag: l.defaultKgPerBag,
      kgPerUnit: l.kgPerUnit,
      boxMode: l.boxMode,
      itemsPerBox: l.itemsPerBox,
      weightPerItem: l.weightPerItem,
      kgPerBox: l.kgPerBox,
      weightPerTin: l.weightPerTin,
    );

String _itemKey(TradePurchaseLine l) {
  final cid = (l.catalogItemId ?? '').trim();
  if (cid.isNotEmpty) return 'cid:$cid';
  return 'n:${l.itemName.trim().toLowerCase()}';
}

String _supplierKey(TradePurchase p) {
  final sid = (p.supplierId ?? '').trim();
  final nm =
      (p.supplierName ?? '').trim().isEmpty ? '-' : p.supplierName!.trim();
  return sid.isNotEmpty ? 'sid:$sid' : 'sn:${nm.toLowerCase()}';
}

String _supplierTitle(TradePurchase p) =>
    (p.supplierName ?? '').trim().isEmpty ? '-' : p.supplierName!.trim();

class _ItemSlice {
  _ItemSlice(this.key, this.title);

  final String key;
  final String title;
  double qty = 0;
  double kg = 0;
  final Set<String> dealIds = {};
}

class _SupSlice {
  _SupSlice(this.key, this.title);

  final String key;
  final String title;
  double bagQty = 0;
  double bagKg = 0;
  double boxQty = 0;
  double tinQty = 0;
  final Set<String> dealIds = {};

  double get deals => dealIds.length.toDouble();
}

class _BrokerSlice {
  _BrokerSlice(this.key, this.title);

  final String key;
  final String title;
  double commission = 0;
  final Set<String> purchaseIds = {};

  double get deals => purchaseIds.length.toDouble();
}

class _Agg {
  _Agg({
    required this.dealsDistinct,
    required this.bucketedKg,
    required this.byItemBag,
    required this.byItemBox,
    required this.byItemTin,
    required this.bySupplier,
    required this.byBroker,
  });

  final int dealsDistinct;
  final double bucketedKg;
  final Map<String, _ItemSlice> byItemBag;
  final Map<String, _ItemSlice> byItemBox;
  final Map<String, _ItemSlice> byItemTin;
  final Map<String, _SupSlice> bySupplier;
  final Map<String, _BrokerSlice> byBroker;

  List<_ItemSlice> sortedItems(_PackKind kind) {
    final m = switch (kind) {
      _PackKind.bag => byItemBag,
      _PackKind.box => byItemBox,
      _PackKind.tin => byItemTin,
    };
    final list = m.values.toList();
    list.sort((a, b) {
      if (kind == _PackKind.bag && (a.kg - b.kg).abs() > 1e-6) {
        return b.kg.compareTo(a.kg);
      }
      if ((a.qty - b.qty).abs() > 1e-6) return b.qty.compareTo(a.qty);
      return a.title.compareTo(b.title);
    });
    return list;
  }
}

_Agg _aggregate(List<TradePurchase> purchases) {
  final bag = <String, _ItemSlice>{};
  final box = <String, _ItemSlice>{};
  final tin = <String, _ItemSlice>{};
  final sup = <String, _SupSlice>{};
  final bro = <String, _BrokerSlice>{};

  var kgSum = 0.0;
  final bucketedPurchaseIds = <String>{};

  for (final p in purchases) {
    final sk = _supplierKey(p);
    final sl = sup.putIfAbsent(sk, () => _SupSlice(sk, _supplierTitle(p)));

    final bid = (p.brokerId ?? '').trim();
    final bnm = (p.brokerName ?? '').trim();
    if (bid.isNotEmpty || bnm.isNotEmpty) {
      final bk = bid.isNotEmpty ? 'bid:$bid' : 'bn:${bnm.toLowerCase()}';
      final bl = bro.putIfAbsent(
          bk, () => _BrokerSlice(bk, bnm.isEmpty ? 'Broker' : bnm));
      if (bl.purchaseIds.add(p.id)) {
        bl.commission += tradePurchaseCommissionInr(p);
      }
    }

    for (final l in p.lines) {
      final bk = _routeLineBucket(l);
      if (bk == null) continue;

      bucketedPurchaseIds.add(p.id);
      sl.dealIds.add(p.id);
      kgSum += _kgLine(l);
      final ik = _itemKey(l);
      final ttl = l.itemName.trim().isEmpty ? '-' : l.itemName.trim();

      switch (bk) {
        case _PackKind.bag:
          final it = bag.putIfAbsent(ik, () => _ItemSlice(ik, ttl));
          it.qty += l.qty;
          it.kg += _kgLine(l);
          it.dealIds.add(p.id);
          sl.bagQty += l.qty;
          sl.bagKg += _kgLine(l);
        case _PackKind.box:
          final it = box.putIfAbsent(ik, () => _ItemSlice(ik, ttl));
          it.qty += l.qty;
          it.dealIds.add(p.id);
          sl.boxQty += l.qty;
        case _PackKind.tin:
          final it = tin.putIfAbsent(ik, () => _ItemSlice(ik, ttl));
          it.qty += l.qty;
          it.dealIds.add(p.id);
          sl.tinQty += l.qty;
      }
    }
  }

  return _Agg(
    dealsDistinct: bucketedPurchaseIds.length,
    bucketedKg: kgSum,
    byItemBag: bag,
    byItemBox: box,
    byItemTin: tin,
    bySupplier: sup,
    byBroker: bro,
  );
}

String _qtyReadable(double q) =>
    q == q.roundToDouble() ? '${q.round()}' : q.toStringAsFixed(1);

String _inr0(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ', decimalDigits: 0)
        .format(n);

enum _DatePreset { today, week, month, year, custom }

String _presetLabel(_DatePreset p) => switch (p) {
      _DatePreset.today => 'Today',
      _DatePreset.week => 'Week',
      _DatePreset.month => 'Month',
      _DatePreset.year => 'Year',
      _DatePreset.custom => 'Custom',
    };

String _kgReadable(double kg) {
  if (kg < 1e-9) return '0';
  if ((kg - kg.roundToDouble()).abs() < 1e-6) return '${kg.round()}';
  return kg.toStringAsFixed(1);
}

List<_SupSlice> _sortedSuppliersFiltered(_Agg agg) {
  final l = agg.bySupplier.values.where((s) => s.dealIds.isNotEmpty).toList();
  l.sort((a, b) {
    final dc = b.dealIds.length.compareTo(a.dealIds.length);
    if (dc != 0) return dc;
    return a.title.compareTo(b.title);
  });
  return l;
}

List<_BrokerSlice> _sortedBrokers(_Agg agg) {
  final l = agg.byBroker.values.toList();
  l.sort((a, b) {
    final c = b.commission.compareTo(a.commission);
    if (c != 0) return c;
    final d = b.purchaseIds.length.compareTo(a.purchaseIds.length);
    if (d != 0) return d;
    return a.title.compareTo(b.title);
  });
  return l;
}

List<_ItemSlice> _filterRowsByQuery(List<_ItemSlice> rows, String q) {
  final t = q.trim().toLowerCase();
  if (t.isEmpty) return rows;
  return rows.where((e) => e.title.toLowerCase().contains(t)).toList();
}

/// Full-screen smart report (shell Reports tab at `/reports`).
class FullReportsPage extends ConsumerStatefulWidget {
  const FullReportsPage({super.key});

  @override
  ConsumerState<FullReportsPage> createState() => _FullReportsPageState();
}

class _FullReportsPageState extends ConsumerState<FullReportsPage> {
  _DatePreset _preset = _DatePreset.month;
  _MainTab _mainTab = _MainTab.items;
  _ItemsSubTab _itemSub = _ItemsSubTab.bag;
  final TextEditingController _searchCtl = TextEditingController();
  int _visibleCap = 5;
  bool _exportingCsv = false;
  bool _exportingPdf = false;

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  void _bumpInvalidate() {
    invalidatePurchaseWorkspace(ref);
    ref.invalidate(smartReportPurchasesProvider);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = ref.read(analyticsDateRangeProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: range.from, end: range.to),
    );
    if (picked == null || !mounted) return;
    ref.read(analyticsDateRangeProvider.notifier).state =
        (from: picked.start, to: picked.end);
    setState(() {
      _preset = _DatePreset.custom;
      _visibleCap = 5;
    });
    _bumpInvalidate();
  }

  void _applyDatePreset(_DatePreset p) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    ref.read(analyticsDateRangeProvider.notifier).state = switch (p) {
      _DatePreset.today => (from: today, to: today),
      _DatePreset.week =>
        (from: today.subtract(const Duration(days: 6)), to: today),
      _DatePreset.month => (from: DateTime(n.year, n.month, 1), to: today),
      _DatePreset.year => (from: DateTime(n.year, 1, 1), to: today),
      _DatePreset.custom => ref.read(analyticsDateRangeProvider),
    };
    setState(() {
      _preset = p;
      _visibleCap = 5;
    });
    _bumpInvalidate();
  }

  Future<void> _exportTableCsv(_Agg agg) async {
    if (_exportingCsv || _exportingPdf) return;
    setState(() => _exportingCsv = true);
    try {
      final range = ref.read(analyticsDateRangeProvider);
      final df = DateFormat('yyyy-MM-dd');
      final qf = _searchCtl.text.trim().toLowerCase();
      final buf = StringBuffer();
      buf.writeln(
        '# Purchase Assistant — Smart Report — ${_mainTab.name} — '
        '${df.format(range.from)} to ${df.format(range.to)}',
      );

      switch (_mainTab) {
        case _MainTab.items:
          final pk = switch (_itemSub) {
            _ItemsSubTab.bag => _PackKind.bag,
            _ItemsSubTab.box => _PackKind.box,
            _ItemsSubTab.tin => _PackKind.tin,
          };
          final raw = agg.sortedItems(pk);
          final rows = _filterRowsByQuery(raw, qf);
          if (rows.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Nothing to export for this view.')),
              );
            }
            return;
          }
          final label = switch (_itemSub) {
            _ItemsSubTab.bag => 'bag',
            _ItemsSubTab.box => 'box',
            _ItemsSubTab.tin => 'tin',
          };
          buf.writeln('bucket,name,qty,bag_kg,deals');
          for (final r in rows) {
            buf.writeln([
              analyticsCsvCell(label),
              analyticsCsvCell(r.title),
              analyticsCsvCell(_qtyReadable(r.qty)),
              analyticsCsvCell(pk == _PackKind.bag ? _kgReadable(r.kg) : '-'),
              analyticsCsvCell('${r.dealIds.length}'),
            ].join(','));
          }
        case _MainTab.suppliers:
          final raw = _sortedSuppliersFiltered(agg);
          final rows = qf.isEmpty
              ? raw
              : raw.where((s) => s.title.toLowerCase().contains(qf)).toList();
          if (rows.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Nothing to export for this view.')),
              );
            }
            return;
          }
          buf.writeln('supplier,bag_qty,bag_kg,box_qty,tin_qty,deals');
          for (final s in rows) {
            buf.writeln([
              analyticsCsvCell(s.title),
              analyticsCsvCell(_qtyReadable(s.bagQty)),
              analyticsCsvCell(_kgReadable(s.bagKg)),
              analyticsCsvCell(_qtyReadable(s.boxQty)),
              analyticsCsvCell(_qtyReadable(s.tinQty)),
              analyticsCsvCell('${s.dealIds.length}'),
            ].join(','));
          }
        case _MainTab.brokers:
          final raw = _sortedBrokers(agg);
          final rows = qf.isEmpty
              ? raw
              : raw.where((b) => b.title.toLowerCase().contains(qf)).toList();
          if (rows.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Nothing to export for this view.')),
              );
            }
            return;
          }
          buf.writeln('broker,commission_inr,deals');
          for (final b in rows) {
            buf.writeln([
              analyticsCsvCell(b.title),
              analyticsCsvCell(b.commission.toStringAsFixed(0)),
              analyticsCsvCell('${b.purchaseIds.length}'),
            ].join(','));
          }
      }

      await Share.share(buf.toString(),
          subject:
              'Smart report ${df.format(range.from)}–${df.format(range.to)}');
    } catch (e) {
      if (mounted) {
        final msg = e is DioException
            ? friendlyApiError(e)
            : 'Something went wrong. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed. $msg')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
  }

  Future<void> _exportStatementPdf(
    BusinessProfile biz,
    _Agg agg,
    DateTime from,
    DateTime to,
  ) async {
    const muted = PdfColor.fromInt(0xFF475569);
    final df = DateFormat('yyyy-MM-dd');
    pw.Widget kv(String k, String v) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(safePdfText(k),
                style: const pw.TextStyle(fontSize: 9, color: muted)),
            pw.Text(
              safePdfText(v),
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget section(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
          child: pw.Text(
            safePdfText(t),
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        );

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => [
          pw.Text(
            safePdfText(biz.legalName),
            style:
                pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            safePdfText('Smart report ${df.format(from)} to ${df.format(to)}'),
            style: pw.TextStyle(fontSize: 11, color: muted),
          ),
          pw.SizedBox(height: 8),
          kv('Deals (bucketed lines)', '${agg.dealsDistinct}'),
          kv('Total kg (bucketed)', _kgReadable(agg.bucketedKg)),
          section('Bag items'),
          ...agg.sortedItems(_PackKind.bag).take(50).map(
                (r) => kv(
                  r.title,
                  'Qty ${_qtyReadable(r.qty)} · Kg ${_kgReadable(r.kg)} · '
                      'Deals ${r.dealIds.length}',
                ),
              ),
          section('Box items'),
          ...agg.sortedItems(_PackKind.box).take(50).map(
                (r) => kv(
                  r.title,
                  'Qty ${_qtyReadable(r.qty)} · Deals ${r.dealIds.length}',
                ),
              ),
          section('Tin items'),
          ...agg.sortedItems(_PackKind.tin).take(50).map(
                (r) => kv(
                  r.title,
                  'Qty ${_qtyReadable(r.qty)} · Deals ${r.dealIds.length}',
                ),
              ),
          section('Suppliers'),
          ..._sortedSuppliersFiltered(agg).take(50).map(
                (s) => kv(
                  s.title,
                  'Bag ${_qtyReadable(s.bagQty)} / ${_kgReadable(s.bagKg)} kg — '
                      'Box ${_qtyReadable(s.boxQty)} — Tin ${_qtyReadable(s.tinQty)} — '
                      'Deals ${s.dealIds.length}',
                ),
              ),
          section('Brokers'),
          ..._sortedBrokers(agg).take(50).map(
                (b) => kv(
                  b.title,
                  '${_inr0(b.commission)} (${b.purchaseIds.length} deals)',
                ),
              ),
        ],
      ),
    );

    final bytes = await doc.save();
    if (!mounted) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Widget _compactRow(
    BuildContext ctx,
    String title,
    List<({String label, String value})> metrics,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            title,
            style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: metrics.map((m) {
              return Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${m.label}: ',
                      style: TextStyle(
                        color: HexaColors.textBody,
                        fontSize: 13,
                      ),
                    ),
                    TextSpan(
                      text: m.value,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _kpiStrip(_Agg agg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: HexaColors.brandCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HexaColors.brandBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deals',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: HexaColors.textBody,
                      ),
                ),
                SelectableText(
                  '${agg.dealsDistinct}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total kg',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: HexaColors.textBody,
                      ),
                ),
                SelectableText(
                  _kgReadable(agg.bucketedKg),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listSegment(_Agg agg) {
    switch (_mainTab) {
      case _MainTab.items:
        final pk = switch (_itemSub) {
          _ItemsSubTab.bag => _PackKind.bag,
          _ItemsSubTab.box => _PackKind.box,
          _ItemsSubTab.tin => _PackKind.tin,
        };
        final all = _filterRowsByQuery(
          agg.sortedItems(pk),
          _searchCtl.text,
        );
        if (all.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No bucketed lines in this range.',
              style: TextStyle(color: HexaColors.textBody),
            ),
          );
        }
        final cap = _visibleCap < all.length ? _visibleCap : all.length;
        final rowWidgets = <Widget>[];
        for (var i = 0; i < cap; i++) {
          final r = all[i];
          final metrics = pk == _PackKind.bag
              ? <({String label, String value})>[
                  (label: 'Qty', value: _qtyReadable(r.qty)),
                  (label: 'Kg', value: _kgReadable(r.kg)),
                  (label: 'Deals', value: '${r.dealIds.length}'),
                ]
              : <({String label, String value})>[
                  (label: 'Qty', value: _qtyReadable(r.qty)),
                  (label: 'Deals', value: '${r.dealIds.length}'),
                ];
          rowWidgets.add(_compactRow(context, r.title, metrics));
          if (i < cap - 1) {
            rowWidgets
                .add(Divider(height: 1, color: HexaColors.brandBorder));
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...rowWidgets,
            if (cap < all.length)
              TextButton(
                onPressed: () => setState(() => _visibleCap = _visibleCap + 5),
                child: const Text('View more'),
              ),
          ],
        );

      case _MainTab.suppliers:
        final all = _searchCtl.text.trim().isEmpty
            ? _sortedSuppliersFiltered(agg)
            : _sortedSuppliersFiltered(agg)
                .where((s) => s.title
                    .toLowerCase()
                    .contains(_searchCtl.text.trim().toLowerCase()))
                .toList();
        if (all.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No suppliers with bucketed lines.',
              style: TextStyle(color: HexaColors.textBody),
            ),
          );
        }
        final cap = _visibleCap < all.length ? _visibleCap : all.length;
        final rowWidgets = <Widget>[];
        for (var i = 0; i < cap; i++) {
          final s = all[i];
          rowWidgets.add(_compactRow(context, s.title, [
            (label: 'Bag qty', value: _qtyReadable(s.bagQty)),
            (label: 'Bag kg', value: _kgReadable(s.bagKg)),
            (label: 'Box', value: _qtyReadable(s.boxQty)),
            (label: 'Tin', value: _qtyReadable(s.tinQty)),
            (label: 'Deals', value: '${s.dealIds.length}'),
          ]));
          if (i < cap - 1) {
            rowWidgets.add(Divider(height: 1, color: HexaColors.brandBorder));
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...rowWidgets,
            if (cap < all.length)
              TextButton(
                onPressed: () => setState(() => _visibleCap = _visibleCap + 5),
                child: const Text('View more'),
              ),
          ],
        );

      case _MainTab.brokers:
        final all = _searchCtl.text.trim().isEmpty
            ? _sortedBrokers(agg)
            : _sortedBrokers(agg)
                .where((b) => b.title
                    .toLowerCase()
                    .contains(_searchCtl.text.trim().toLowerCase()))
                .toList();
        if (all.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No broker-tagged purchases in range.',
              style: TextStyle(color: HexaColors.textBody),
            ),
          );
        }
        final cap = _visibleCap < all.length ? _visibleCap : all.length;
        final rowWidgets = <Widget>[];
        for (var i = 0; i < cap; i++) {
          final b = all[i];
          rowWidgets.add(_compactRow(context, b.title, [
            (label: 'Commission', value: _inr0(b.commission)),
            (label: 'Deals', value: '${b.purchaseIds.length}'),
          ]));
          if (i < cap - 1) {
            rowWidgets.add(Divider(height: 1, color: HexaColors.brandBorder));
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...rowWidgets,
            if (cap < all.length)
              TextButton(
                onPressed: () => setState(() => _visibleCap = _visibleCap + 5),
                child: const Text('View more'),
              ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final purchasesAsync = ref.watch(smartReportPurchasesProvider);
    final session = ref.watch(sessionProvider);
    final range = ref.watch(analyticsDateRangeProvider);
    final rangeFmt =
        '${DateFormat('d MMM').format(range.from)} → ${DateFormat('d MMM').format(range.to)}';

    Future<void> onSharePdfPressed() async {
      if (_exportingPdf || _exportingCsv) return;
      final list = purchasesAsync.valueOrNull ?? const <TradePurchase>[];
      if (list.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nothing to export for this period.')),
          );
        }
        return;
      }
      setState(() => _exportingPdf = true);
      try {
        final agg = _aggregate(list);
        final biz = ref.read(invoiceBusinessProfileProvider);
        await _exportStatementPdf(biz, agg, range.from, range.to);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF export failed: $e')),
        );
      } finally {
        if (mounted) setState(() => _exportingPdf = false);
      }
    }

    Future<void> onShareCsvPressed() async {
      final list = purchasesAsync.valueOrNull ?? const <TradePurchase>[];
      if (list.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nothing to export for this period.')),
          );
        }
        return;
      }
      await _exportTableCsv(_aggregate(list));
    }

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: GoRouter.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              )
            : null,
        title: const Text('Reports'),
        backgroundColor: HexaColors.brandBackground,
        foregroundColor: HexaColors.brandPrimary,
        actions: [
          IconButton(
            tooltip: 'Export statement PDF',
            onPressed:
                (_exportingCsv || _exportingPdf) ? null : onSharePdfPressed,
            icon: _exportingPdf
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_rounded),
          ),
          IconButton(
            tooltip: 'Export CSV',
            onPressed:
                (_exportingCsv || _exportingPdf) ? null : onShareCsvPressed,
            icon: _exportingCsv
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share_rounded),
          ),
          ShellQuickRefActions(
            onRefresh: _bumpInvalidate,
          ),
        ],
      ),
      body: session == null
          ? const Center(child: Text('Sign in'))
          : RefreshIndicator(
              onRefresh: () async {
                _bumpInvalidate();
                await ref.read(smartReportPurchasesProvider.future);
              },
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 120),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    color: HexaColors.brandCard,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: HexaColors.brandBorder),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
                      child: Row(
                        children: [
                          PopupMenuButton<_DatePreset>(
                            tooltip: 'Date range',
                            onSelected: (p) {
                              if (p == _DatePreset.custom) {
                                _pickCustomRange();
                              } else {
                                _applyDatePreset(p);
                              }
                            },
                            itemBuilder: (ctx) => _DatePreset.values
                                .map(
                                  (p) => PopupMenuItem(
                                    value: p,
                                    child: Text(_presetLabel(p)),
                                  ),
                                )
                                .toList(),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _presetLabel(_preset),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const Icon(Icons.expand_more_rounded, size: 18),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(
                              rangeFmt,
                              style: TextStyle(
                                fontSize: 12,
                                color: HexaColors.textBody,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<_MainTab>(
                    segments: const [
                      ButtonSegment(
                          value: _MainTab.items, label: Text('Items')),
                      ButtonSegment(
                          value: _MainTab.suppliers, label: Text('Suppliers')),
                      ButtonSegment(
                          value: _MainTab.brokers, label: Text('Brokers')),
                    ],
                    selected: {_mainTab},
                    onSelectionChanged: (s) {
                      if (s.isEmpty) return;
                      setState(() {
                        _mainTab = s.first;
                        _visibleCap = 5;
                      });
                    },
                  ),
                  if (_mainTab == _MainTab.items) ...[
                    const SizedBox(height: 8),
                    SegmentedButton<_ItemsSubTab>(
                      segments: const [
                        ButtonSegment(
                            value: _ItemsSubTab.bag, label: Text('Bag')),
                        ButtonSegment(
                            value: _ItemsSubTab.box, label: Text('Box')),
                        ButtonSegment(
                            value: _ItemsSubTab.tin, label: Text('Tin')),
                      ],
                      selected: {_itemSub},
                      onSelectionChanged: (s) {
                        if (s.isEmpty) return;
                        setState(() {
                          _itemSub = s.first;
                          _visibleCap = 5;
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchCtl,
                    onChanged: (_) => setState(() => _visibleCap = 5),
                    decoration: InputDecoration(
                      hintText: 'Search',
                      isDense: true,
                      filled: true,
                      fillColor: HexaColors.brandCard,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: HexaColors.brandBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: HexaColors.brandBorder),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  purchasesAsync.when(
                    skipLoadingOnReload: true,
                    loading: () => const ListSkeleton(
                      rowCount: 5,
                      rowHeight: 72,
                      padding: EdgeInsets.fromLTRB(0, 0, 0, 24),
                    ),
                    error: (_, __) => FriendlyLoadError(
                      message: 'Unable to load purchases',
                      onRetry: () =>
                          ref.invalidate(smartReportPurchasesProvider),
                    ),
                    data: (list) {
                      final agg = _aggregate(list);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _kpiStrip(agg),
                          _listSegment(agg),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }
}
