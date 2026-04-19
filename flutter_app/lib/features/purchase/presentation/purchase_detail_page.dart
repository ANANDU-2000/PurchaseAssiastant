import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/services/purchase_pdf.dart';
import '../../../core/theme/hexa_colors.dart';

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(n);

final _purchaseDetailProvider = FutureProvider.autoDispose
    .family<TradePurchase, String>((ref, purchaseId) async {
  final session = ref.watch(sessionProvider);
  if (session == null) throw StateError('no session');
  final m = await ref.read(hexaApiProvider).getTradePurchase(
        businessId: session.primaryBusiness.id,
        purchaseId: purchaseId,
      );
  return TradePurchase.fromJson(m);
});

class PurchaseDetailPage extends ConsumerWidget {
  const PurchaseDetailPage({super.key, required this.purchaseId});

  final String purchaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_purchaseDetailProvider(purchaseId));
    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: const Text('Purchase'),
        backgroundColor: HexaColors.brandBackground,
        foregroundColor: HexaColors.brandPrimary,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(_purchaseDetailProvider(purchaseId)),
            child: const Text('Retry'),
          ),
        ),
        data: (p) => _DetailBody(
          p: p,
          onRefresh: () => ref.invalidate(_purchaseDetailProvider(purchaseId)),
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.p, required this.onRefresh});
  final TradePurchase p;
  final VoidCallback onRefresh;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final st = p.statusEnum;
    return RefreshIndicator(
      onRefresh: () async {
        widget.onRefresh();
        await ref.read(_purchaseDetailProvider(p.id).future);
      },
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          _headerCard(p, st),
          const SizedBox(height: 12),
          _itemsCard(p),
          const SizedBox(height: 12),
          _paymentCard(p),
          const SizedBox(height: 12),
          _actionsRow(context, ref, p),
        ],
      ),
    );
  }

  Widget _headerCard(TradePurchase p, PurchaseStatus st) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.supplierName ?? 'Supplier',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: st.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    st.label,
                    style: TextStyle(
                      color: st.color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            if (p.brokerName != null) Text('Broker: ${p.brokerName}'),
            Text('${p.humanId} · ${DateFormat.yMMMd().format(p.purchaseDate)}'),
          ],
        ),
      ),
    );
  }

  Widget _itemsCard(TradePurchase p) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Items', style: TextStyle(fontWeight: FontWeight.w800)),
            const Divider(),
            for (final l in p.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.itemName, maxLines: 2),
                          if (l.unit.toLowerCase() == 'bag' &&
                              l.defaultKgPerBag != null &&
                              l.defaultKgPerBag! > 0)
                            Text(
                              '${l.qty.toStringAsFixed(l.qty == l.qty.roundToDouble() ? 0 : 1)} bag → '
                              '${(l.qty * l.defaultKgPerBag!).toStringAsFixed(1)} kg @ ${_inr(l.landingCost.round())}/bag',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                height: 1.25,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${l.qty} ${l.unit}'),
                        Text(
                          _inr((l.qty * l.landingCost).round()),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _paymentCard(TradePurchase p) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Payment', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _kv('Total', _inr(p.totalAmount.round())),
            _kv('Paid', _inr(p.paidAmount.round())),
            _kv('Remaining', _inr(p.remaining.round())),
            if (p.dueDate != null)
              _kv('Due', DateFormat.yMMMd().format(p.dueDate!)),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: HexaColors.neutral)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _actionsRow(BuildContext context, WidgetRef ref, TradePurchase p) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: p.statusEnum == PurchaseStatus.cancelled
              ? null
              : () => context.push('/purchase/edit/${p.id}'),
          icon: const Icon(Icons.edit_rounded, size: 18),
          label: const Text('Edit'),
        ),
        FilledButton.icon(
          onPressed: p.statusEnum == PurchaseStatus.paid ||
                  p.statusEnum == PurchaseStatus.cancelled
              ? null
              : () => _markPaidSheet(context, ref, p),
          icon: const Icon(Icons.payments_rounded, size: 18),
          label: const Text('Mark paid'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final biz = ref.read(invoiceBusinessProfileProvider);
            await sharePurchasePdf(p, biz);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PDF ready to share')),
              );
            }
          },
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
          label: const Text('PDF'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final biz = ref.read(invoiceBusinessProfileProvider);
            try {
              await downloadPurchasePdf(p, biz);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      kIsWeb
                          ? 'Use the browser print/save dialog to download PDF'
                          : 'Use “Save as PDF” or share from the dialog to save the file',
                    ),
                  ),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
              }
            }
          },
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Download'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final biz = ref.read(invoiceBusinessProfileProvider);
            await printPurchasePdf(p, biz);
          },
          icon: const Icon(Icons.print_rounded, size: 18),
          label: const Text('Print'),
        ),
        OutlinedButton.icon(
          onPressed: () => _whatsappPurchasePdf(context, ref, p),
          icon: const Icon(Icons.chat_rounded, size: 18),
          label: const Text('WhatsApp'),
        ),
      ],
    );
  }

  String? _waPhoneDigits(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length < 10) return null;
    if (d.length == 10) return '91$d';
    return d;
  }

  Future<void> _whatsappPurchasePdf(
      BuildContext context, WidgetRef ref, TradePurchase p) async {
    final biz = ref.read(invoiceBusinessProfileProvider);
    await sharePurchasePdf(p, biz);
    if (!context.mounted) return;
    final digits = _waPhoneDigits(p.supplierWhatsapp ?? p.supplierPhone);
    if (digits == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF shared. Add supplier WhatsApp or phone to open a chat.'),
        ),
      );
      return;
    }
    final msg = Uri.encodeComponent(
      '${p.humanId} — Total ${_inr(p.totalAmount.round())}, Remaining ${_inr(p.remaining.round())}. (Attach the PDF from the share sheet.)',
    );
    final u = Uri.parse('https://wa.me/$digits?text=$msg');
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _markPaidSheet(BuildContext context, WidgetRef ref, TradePurchase p) async {
    final ctrl = TextEditingController(text: p.remaining.toStringAsFixed(0));
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Record payment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount paid (total on purchase)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final v = double.tryParse(ctrl.text.trim());
    if (v == null || v < 0) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).patchPurchasePayment(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
            paidAmount: v,
          );
      ref.invalidate(tradePurchasesListProvider);
      ref.invalidate(_purchaseDetailProvider(p.id));
      invalidateBusinessAggregates(ref);
      widget.onRefresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment saved')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }
}
