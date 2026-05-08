import 'package:flutter/material.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import 'scan_draft_table_widgets.dart';

List<Map<String, dynamic>> scanDraftCandidatesOf(Object? x) {
  if (x is! Map) return const [];
  final c = x['candidates'];
  if (c is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final e in c.take(3)) {
    if (e is Map) out.add(Map<String, dynamic>.from(e));
  }
  return out;
}

Widget scanDraftSupplierBrokerCard({
  required Map<String, dynamic> scan,
  required void Function(String key, Map<String, dynamic> cand) onPickCandidate,
}) {
  final sup = scan['supplier'];
  final bro = scan['broker'];
  String supName() {
    if (sup is Map) {
      return (sup['matched_name']?.toString().trim().isNotEmpty == true)
          ? sup['matched_name'].toString()
          : (sup['raw_text']?.toString() ?? '—');
    }
    return '—';
  }

  double supConf() =>
      (sup is Map && sup['confidence'] is num) ? (sup['confidence'] as num).toDouble() : 0.0;

  String broName() {
    if (bro is Map) {
      return (bro['matched_name']?.toString().trim().isNotEmpty == true)
          ? bro['matched_name'].toString()
          : (bro['raw_text']?.toString() ?? '—');
    }
    return '—';
  }

  double broConf() =>
      (bro is Map && bro['confidence'] is num) ? (bro['confidence'] as num).toDouble() : 0.0;

  final supCands = scanDraftCandidatesOf(sup);
  final broCands = scanDraftCandidatesOf(bro);

  return Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Supplier', style: HexaDsType.formSectionLabel),
                    const SizedBox(height: 4),
                    Text(supName(),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    if (supCands.isNotEmpty && supConf() < 0.92) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final c in supCands)
                            OutlinedButton(
                              onPressed: () => onPickCandidate('supplier', c),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(
                                (c['name'] ?? 'Select').toString(),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              scanDraftConfidencePill(supConf()),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Broker', style: HexaDsType.formSectionLabel),
                    const SizedBox(height: 4),
                    Text(broName(),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    if (broCands.isNotEmpty && broConf() < 0.92) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final c in broCands)
                            OutlinedButton(
                              onPressed: () => onPickCandidate('broker', c),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(
                                (c['name'] ?? 'Select').toString(),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              scanDraftConfidencePill(broConf()),
            ],
          ),
        ],
      ),
    ),
  );
}

Widget scanDraftChargesCard(Map<String, dynamic> scan) {
  final charges = scan['charges'];
  if (charges is! Map) return const SizedBox.shrink();
  final ch = Map<String, dynamic>.from(charges);
  final delivered = ch['delivered_rate'];
  final billty = ch['billty_rate'];
  final freight = ch['freight_amount'];
  final paymentDaysRaw = scan['payment_days'];
  final int? paymentDays = paymentDaysRaw is int
      ? paymentDaysRaw
      : (paymentDaysRaw is num ? paymentDaysRaw.round() : int.tryParse(paymentDaysRaw?.toString() ?? ''));
  final hasAny = delivered != null || billty != null || freight != null || paymentDays != null;
  if (!hasAny) return const SizedBox.shrink();

  String fmtMoney(Object? v) {
    if (v is num) return '₹${v.toStringAsFixed(0)}';
    return '—';
  }

  Widget chip(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$k $v', style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }

  return Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Terms & charges', style: HexaDsType.formSectionLabel),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (freight is num) chip('Freight', fmtMoney(freight)),
              if (delivered is num) chip('Delivered', fmtMoney(delivered)),
              if (billty is num) chip('Billty', fmtMoney(billty)),
              if (paymentDays != null) chip('Payment', '$paymentDays days'),
            ],
          ),
        ],
      ),
    ),
  );
}

Widget scanDraftWarningsCard(Map<String, dynamic> scan) {
  final warns = scan['warnings'];
  if (warns is! List || warns.isEmpty) return const SizedBox.shrink();
  final first = warns.take(3).toList();
  return Card(
    margin: EdgeInsets.zero,
    color: const Color(0xFFFFFBEB),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Needs review',
            style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF92400E)),
          ),
          const SizedBox(height: 6),
          for (final w in first)
            if (w is Map && (w['message']?.toString().trim().isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${w['message']}',
                  style: const TextStyle(color: Color(0xFF92400E), fontWeight: FontWeight.w600),
                ),
              ),
        ],
      ),
    ),
  );
}
