import 'dart:async';
import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/router/post_auth_route.dart' show sessionCanSeeFinancials;
import '../../../core/errors/barcode_operation_errors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../../core/services/pdf_actions.dart';
import '../../stock/presentation/widgets/edit_item_code_sheet.dart';
import '../services/barcode_pdf_service.dart';

class BarcodePrintPage extends ConsumerStatefulWidget {
  const BarcodePrintPage({super.key, required this.itemId, this.preloadItemId});

  final String itemId;
  final String? preloadItemId;

  @override
  ConsumerState<BarcodePrintPage> createState() => _BarcodePrintPageState();
}

class _BarcodePrintPageState extends ConsumerState<BarcodePrintPage> {
  final LabelSize _size = LabelSize.small;
  int _copies = 1;
  final bool _showLastPurchase = true;
  bool _busy = false;
  bool _loadError = false;
  String? _loadErrorMessage;
  Map<String, dynamic>? _data;

  String _resolveItemId() {
    final fromRoute = widget.itemId.trim();
    if (fromRoute.isNotEmpty && fromRoute != 'new') return fromRoute;
    final preload = widget.preloadItemId?.trim();
    if (preload != null && preload.isNotEmpty) return preload;
    if (!mounted) return '';
    final q = GoRouterState.of(context).uri.queryParameters;
    return (q['preloadItemId'] ?? q['itemId'] ?? '').trim();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() {
      _loadError = false;
      _data = null;
    });
    final bid = session.primaryBusiness.id;
    final api = ref.read(hexaApiProvider);
    try {
      final itemId = _resolveItemId();
      if (itemId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loadError = true;
          _loadErrorMessage = 'No item selected for label print.';
        });
        return;
      }
      final j = await api.getBarcodeLabel(businessId: bid, itemId: itemId);
      if (!mounted) return;
      setState(() => _data = j);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = true;
        _loadErrorMessage = barcodeMessageForUser(
          e,
          ctx: BarcodeOperationContext.singlePrint,
        );
      });
    }
  }

  BarcodeLabelData? get _label {
    final d = _data;
    if (d == null) return null;
    return BarcodeLabelData.fromApiMap(d);
  }

  String _singleBarcodeFilename(BarcodeLabelData label) {
    final code = label.itemCode
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    return 'harisree_barcode_${code.isEmpty ? 'item' : code}_$date.pdf';
  }

  Future<void> _print() async {
    final label = _label;
    if (label == null) return;
    setState(() => _busy = true);
    try {
      final session = ref.read(sessionProvider);
      final hideFinancials =
          session == null || !sessionCanSeeFinancials(session);
      final bytes = await BarcodePdfService.generateSingleLabel(
        data: label,
        size: _size,
        copies: _copies,
        showLastPurchase: _showLastPurchase,
        hideFinancials: hideFinancials,
      );
      if (kIsWeb) {
        await _openLabelPdfPreview(bytes, label);
        return;
      }
      final result = await printPdfBytes(
        buildBytes: () async => bytes,
        filename: _singleBarcodeFilename(label),
        source: 'barcode_print_page',
      );
      if (!result.ok && mounted) _showSnack(result.message);
    } on BarcodeOperationException catch (e) {
      if (!mounted) return;
      _showSnack(e.message);
    } catch (e, st) {
      logBarcodeOperationError(e, st);
      if (!mounted) return;
      _showSnack(
          barcodeMessageForUser(e, ctx: BarcodeOperationContext.singlePrint));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openLabelPdfPreview(
      Uint8List bytes, BarcodeLabelData label) async {
    if (!mounted) return;
    final name = _singleBarcodeFilename(label);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: Text(label.itemName),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  final result = await savePdfBytes(
                    buildBytes: () async => bytes,
                    filename: name,
                    subject: 'Barcode label - ${label.itemName}',
                    source: 'barcode_print_page',
                  );
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(result.message),
                      duration: const Duration(seconds: 5),
                    ),
                  );
                },
                icon: const Icon(Icons.download_rounded),
                label: const Text('Download PDF'),
              ),
            ],
          ),
          body: PdfPreview(
            build: (_) async => bytes,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
            actions: const [],
          ),
        ),
      ),
    );
  }

  Future<void> _download() async {
    final label = _label;
    if (label == null) return;
    setState(() => _busy = true);
    try {
      final session = ref.read(sessionProvider);
      final hideFinancials =
          session == null || !sessionCanSeeFinancials(session);
      final bytes = await BarcodePdfService.generateSingleLabel(
        data: label,
        size: _size,
        copies: _copies,
        showLastPurchase: _showLastPurchase,
        hideFinancials: hideFinancials,
      );
      if (kIsWeb) {
        await _openLabelPdfPreview(bytes, label);
        return;
      }
      final result = await savePdfBytes(
        buildBytes: () async => bytes,
        filename: _singleBarcodeFilename(label),
        subject: 'Barcode label - ${label.itemName}',
        source: 'barcode_print_page',
      );
      if (!result.ok && mounted) _showSnack(result.message);
    } on BarcodeOperationException catch (e) {
      if (!mounted) return;
      _showSnack(e.message);
    } catch (e, st) {
      logBarcodeOperationError(e, st);
      if (!mounted) return;
      _showSnack(
          barcodeMessageForUser(e, ctx: BarcodeOperationContext.singlePrint));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        backgroundColor: Colors.red.shade700,
        action: SnackBarAction(label: 'Dismiss', onPressed: () {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = _label;

    return Scaffold(
      appBar: AppBar(
        title: Text(label != null ? label.itemName : 'Print label'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(minHeight: 4),
              )
            : null,
        actions: [
          if (label != null)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'download') {
                  unawaited(_download());
                } else if (v == 'edit_code') {
                  final l = _label;
                  if (l == null) return;
                  unawaited(() async {
                    final ok = await showEditItemCodeSheet(
                      context: context,
                      ref: ref,
                      itemId: widget.itemId,
                      itemName: l.itemName,
                      currentCode: l.itemCode,
                    );
                    if (ok) await _load();
                  }());
                }
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(
                  value: 'edit_code',
                  child: Text('Edit item code'),
                ),
                PopupMenuItem(
                  value: 'download',
                  child: Text('Download PDF'),
                ),
              ],
            ),
        ],
      ),
      body: _buildBody(label),
    );
  }

  Widget _buildBody(BarcodeLabelData? label) {
    if (_loadError) {
      return FriendlyLoadError(
        message: _loadErrorMessage ?? 'Could not load label data',
        onRetry: _load,
      );
    }
    if (_data == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: ListSkeleton(),
      );
    }
    if (label == null || label.symbologyValue.isEmpty) {
      return const Center(child: Text('No label data'));
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        24 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [
        if (_busy)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Generating label…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: HexaColors.brandPrimary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        Text('LABEL PREVIEW',
            style: HexaDsType.label(10, color: HexaDsColors.textMuted)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300, width: 1.5),
            boxShadow: [
              BoxShadow(
                blurRadius: 8,
                color: Colors.black.withValues(alpha: 0.08),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                label.itemName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              SvgPicture.string(
                Barcode.code128().toSvg(
                  label.symbologyValue,
                  width: 220,
                  height: 60,
                  drawText: false,
                ),
                width: 220,
                height: 60,
              ),
              const SizedBox(height: 4),
              Text(
                'Item code: ${label.itemCode}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (label.barcode != null && label.barcode!.trim().isNotEmpty)
                Text(
                  'Barcode: ${label.barcode}',
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                ),
              if (label.usesItemIdFallback)
                const Text(
                  'No barcode — using item ID',
                  style: TextStyle(fontSize: 10, color: Colors.black54),
                ),
              if (label.unit != null && label.unit!.isNotEmpty)
                Text('Unit: ${label.unit}',
                    style: const TextStyle(fontSize: 10)),
              if (_size != LabelSize.small &&
                  _showLastPurchase &&
                  label.lastPurchaseDate != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Last: ${DateFormat('dd MMM yy').format(label.lastPurchaseDate!)}  '
                    '${label.lastPurchaseQty?.toStringAsFixed(0) ?? ''} '
                    '${label.lastPurchaseUnit ?? label.unit ?? ''}  '
                    '₹${label.lastPurchaseRate?.toStringAsFixed(0) ?? '—'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 9),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Copies'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: _copies > 1 ? () => setState(() => _copies--) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_copies', style: HexaDsType.heading(18)),
              IconButton(
                onPressed:
                    _copies < 100 ? () => setState(() => _copies++) : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : (kIsWeb ? _download : _print),
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Icon(kIsWeb ? Icons.download_rounded : Icons.print_rounded),
          label: Text(
            _busy
                ? 'Preparing…'
                : (kIsWeb ? 'Download label PDF' : 'Print label'),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: HexaColors.brandPrimary,
            minimumSize: const Size.fromHeight(52),
          ),
        ),
      ],
    );
  }
}
