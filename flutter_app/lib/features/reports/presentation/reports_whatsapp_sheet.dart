import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/business_profile.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/reporting/trade_report_aggregate.dart'
    show
        TradeReportAgg,
        TradeReportItemRow,
        TradeReportTotals,
        TradeReportItemSort,
        sortTradeReportItemsAll;
import '../../../core/services/reports_pdf.dart';
import '../../../core/theme/hexa_colors.dart';
import '../reports_prefs.dart';

String _digitsOnly(String s) {
  final b = StringBuffer();
  for (final c in s.runes) {
    final ch = String.fromCharCode(c);
    if (ch.contains(RegExp(r'[0-9]'))) b.write(ch);
  }
  return b.toString();
}

String _buildSummaryText({
  required String businessLabel,
  required DateTime from,
  required DateTime to,
  required TradeReportAgg agg,
  int topN = 5,
}) {
  final df = DateFormat('MMMM yyyy');
  final head = 'Purchase Report (${df.format(from)})\n\n';
  final t = agg.totals;
  final parts = <String>[
    'Total: ${_inrPlain(t.inr)}',
    _qtyLinePlain(t),
    '',
    'Top items:',
  ];
  final items = sortTradeReportItemsAll(
    List.of(agg.itemsAll),
    TradeReportItemSort.highQty,
  ).take(topN);
  var i = 0;
  for (final r in items) {
    i++;
    final q = reportQtySummaryPlain(r);
    parts.add('$i. ${r.name} — $q — ${_inrPlain(r.amountInr)}');
  }
  return head + parts.join('\n');
}

String _inrPlain(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

String _qtyLinePlain(TradeReportTotals t) {
  final p = <String>[];
  if (t.kg > 1e-9) p.add('${_kgPlain(t.kg)} KG');
  if (t.bags > 1e-9) p.add('${_qtyPlain(t.bags)} BAGS');
  if (t.boxes > 1e-9) p.add('${_qtyPlain(t.boxes)} BOX');
  if (t.tins > 1e-9) p.add('${_qtyPlain(t.tins)} TIN');
  return p.join(' • ');
}

String _kgPlain(double kg) =>
    (kg - kg.roundToDouble()).abs() < 1e-6 ? '${kg.round()}' : kg.toStringAsFixed(1);

String _qtyPlain(double q) =>
    (q - q.roundToDouble()).abs() < 1e-6 ? '${q.round()}' : q.toStringAsFixed(1);

String reportQtySummaryPlain(TradeReportItemRow r) {
  final p = <String>[];
  if (r.kg > 1e-9) p.add('${_kgPlain(r.kg)} KG');
  if (r.bags > 1e-9) p.add('${_qtyPlain(r.bags)} BAGS');
  if (r.boxes > 1e-9) p.add('${_qtyPlain(r.boxes)} BOX');
  if (r.tins > 1e-9) p.add('${_qtyPlain(r.tins)} TIN');
  return p.join(' • ');
}

class ReportsWhatsAppSheet extends StatefulWidget {
  const ReportsWhatsAppSheet({
    super.key,
    required this.agg,
    required this.from,
    required this.to,
    required this.business,
    required this.purchases,
    this.businessLabel = 'My business',
  });

  final TradeReportAgg agg;
  final DateTime from;
  final DateTime to;
  final BusinessProfile business;
  final List<TradePurchase> purchases;
  final String businessLabel;

  @override
  State<ReportsWhatsAppSheet> createState() => _ReportsWhatsAppSheetState();
}

class _ReportsWhatsAppSheetState extends State<ReportsWhatsAppSheet> {
  late final TextEditingController _phone =
      TextEditingController(text: '');
  String _freq = 'weekly';
  bool _sharingPdf = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await ReportsPrefs.getPhone();
    final f = await ReportsPrefs.getFrequency();
    if (!mounted) return;
    setState(() {
      if (p != null) _phone.text = p;
      _freq = f;
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ReportsPrefs.setPhone(_phone.text);
    await ReportsPrefs.setFrequency(_freq);
    if (!mounted) return;
    context.pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved — use Send to open WhatsApp')),
    );
  }

  Future<void> _sharePdf() async {
    if (_sharingPdf) return;
    if (widget.purchases.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No purchases in this range to export.')),
      );
      return;
    }
    setState(() => _sharingPdf = true);
    try {
      final bytes = await buildTradeStatementSsotPdfBytes(
        business: widget.business,
        from: widget.from,
        to: widget.to,
        purchases: widget.purchases,
      );
      final safe = DateFormat('yyyyMMdd').format(widget.from);
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: 'trade_report_$safe.pdf',
          ),
        ],
        text: 'Purchase report (PDF)',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF share failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _sharingPdf = false);
    }
  }

  Future<void> _send() async {
    final raw = _digitsOnly(_phone.text);
    if (raw.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid phone number (digits only).')),
      );
      return;
    }
    final text = _buildSummaryText(
      businessLabel: widget.businessLabel,
      from: widget.from,
      to: widget.to,
      agg: widget.agg,
    );
    final uri = Uri.parse(
      'https://wa.me/$raw?text=${Uri.encodeComponent(text)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'WhatsApp report (MVP)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'We open WhatsApp with a prefilled summary. Use Share PDF to open the system sheet, then pick WhatsApp and attach the file if you like.',
            style: TextStyle(fontSize: 13, color: HexaColors.textBody, height: 1.35),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone (country code + number, digits only)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _freq,
            decoration: const InputDecoration(
              labelText: 'Reminder frequency',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'daily', child: Text('Daily')),
              DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
              DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _freq = v);
            },
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _send,
            child: const Text('Open WhatsApp with summary'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _sharingPdf ? null : _sharePdf,
            child: _sharingPdf
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Share PDF (system sheet)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _save,
            child: const Text('Save phone & frequency'),
          ),
        ],
      ),
    );
  }
}
