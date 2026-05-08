import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/services/offline_store.dart';
import '../../../core/theme/hexa_colors.dart';

import '../mapping/ai_scan_purchase_draft_map.dart';
import 'purchase_scan_draft_map_provider.dart';
import 'scan_draft_edit_item_sheet.dart';

enum _ScanStage {
  idle,
  preparingImage,
  uploading,
  extractingText,
  parsingItems,
  matchingSuppliers,
  validating,
  readyForReview,
  done,
  error,
}

class ScanPurchaseV2Page extends ConsumerStatefulWidget {
  const ScanPurchaseV2Page({super.key});

  @override
  ConsumerState<ScanPurchaseV2Page> createState() => _ScanPurchaseV2PageState();
}

class _ScanPurchaseV2PageState extends ConsumerState<ScanPurchaseV2Page> {
  List<int>? _jpegBytes;
  bool _busy = false;
  _ScanStage _stage = _ScanStage.idle;
  String? _error;
  String? _scanIssue;
  bool _scanIssueBlocker = false;
  String? _queuedScanId;

  Map<String, dynamic>? _scan; // raw ScanResult JSON (table-first UI)
  double _stageProgress = 0;

  final ScrollController _scroll = ScrollController();

  Timer? _stageTimer;
  Timer? _pollTimer;

  @override
  void dispose() {
    _stageTimer?.cancel();
    _pollTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<List<int>> _compressForUpload(List<int> raw) async {
    final decoded = img.decodeImage(Uint8List.fromList(raw));
    if (decoded == null) return Uint8List.fromList(raw);
    const maxW = 1600;
    final resized =
        decoded.width > maxW ? img.copyResize(decoded, width: maxW) : decoded;
    return List<int>.from(img.encodeJpg(resized, quality: 82));
  }

  Future<void> _pick(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src);
    if (x == null) return;
    final raw = await x.readAsBytes();
    _stageTimer?.cancel();
    _pollTimer?.cancel();
    setState(() {
      _scan = null;
      _error = null;
      _busy = false;
      _stage = _ScanStage.idle;
      _jpegBytes = null;
    });
    try {
      final compressed = await _compressForUpload(raw);
      setState(() => _jpegBytes = compressed);
    } catch (_) {
      setState(() => _jpegBytes = raw);
    }
  }

  Future<void> _loadFirstQueuedScanAndStart() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final jobs = OfflineStore.getPendingScanJobs(session.primaryBusiness.id);
    if (jobs.isEmpty) {
      setState(() => _error = 'No offline scans found.');
      return;
    }
    final bytes = OfflineStore.scanJobBytes(jobs.first);
    if (bytes == null || bytes.isEmpty) {
      setState(() => _error = 'Offline scan data is corrupted. Please retake the photo.');
      return;
    }
    setState(() {
      _jpegBytes = bytes;
      _queuedScanId = jobs.first['id']?.toString();
      _error = null;
      _scan = null;
      _stage = _ScanStage.idle;
    });
    await _scanNow();
  }

  _ScanStage _mapServerStage(String? s) {
    final v = (s ?? '').trim().toLowerCase();
    return switch (v) {
      'preparing_image' => _ScanStage.preparingImage,
      'paper_detected' => _ScanStage.preparingImage,
      'uploading' => _ScanStage.uploading,
      'extracting_text' => _ScanStage.extractingText,
      'parsing_items' => _ScanStage.parsingItems,
      'matching' => _ScanStage.matchingSuppliers,
      'validating' => _ScanStage.validating,
      'ready' => _ScanStage.readyForReview,
      'error' => _ScanStage.error,
      _ => _ScanStage.preparingImage,
    };
  }

  Future<void> _scanNow() async {
    final session = ref.read(sessionProvider);
    final bytes = _jpegBytes;
    if (session == null || bytes == null || bytes.isEmpty) return;
    if (_busy) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = true;
      _error = null;
      _scanIssue = null;
      _scanIssueBlocker = false;
      _scan = null;
      _stageProgress = 0;
      _stage = _ScanStage.preparingImage;
    });
    _stageTimer?.cancel();
    _pollTimer?.cancel();
    try {
      // Start async scan (v3) and poll true backend stages.
      final started =
          await ref.read(hexaApiProvider).scanPurchaseBillV3StartMultipart(
            businessId: session.primaryBusiness.id,
            imageBytes: bytes,
            filename: 'bill_scan.jpg',
          );
      final queued = _queuedScanId;
      if (queued != null && queued.isNotEmpty) {
        // Mark as uploaded once we successfully got a scan token.
        unawaited(OfflineStore.markScanJobStatus(queued, 'uploaded'));
        setState(() => _queuedScanId = null);
      }
      final token = started['scan_token']?.toString().trim();
      if (token == null || token.isEmpty) {
        throw StateError('missing scan_token');
      }

      Future<void> pollOnce() async {
        final res = await ref.read(hexaApiProvider).scanPurchaseBillV3Status(
              businessId: session.primaryBusiness.id,
              scanToken: token,
            );
        if (!mounted) return;
        final meta = res['scan_meta'];
        _ScanStage? nextStage;
        double? nextProg;
        String? nextIssue;
        bool nextIssueBlocker = false;
        if (meta is Map) {
          nextStage = _mapServerStage(meta['stage']?.toString());
          final prog = meta['stage_progress'];
          if (prog is num) {
            nextProg = prog.clamp(0.0, 1.0).toDouble();
          }
          final code = meta['error_code']?.toString().trim();
          final stage = meta['error_stage']?.toString().trim();
          if (code != null && code.isNotEmpty) {
            final msg = switch (code) {
              'NOT_A_BILL' =>
                'This photo does not look like a purchase bill. Take a clear photo of your bill or broker note.',
              'OCR_EMPTY' =>
                'Could not fully read handwriting from this photo. Review highlighted fields and correct anything missing.',
              'PARSE_EMPTY' =>
                'Could not fully parse the note structure. You can still edit supplier/items manually before creating the purchase.',
              'OCR_FAILED' =>
                'Text extraction failed for this image. Retake the photo (better light, less blur) or enter details manually.',
              _ => 'Scan needs review. Please confirm the extracted fields.',
            };
            nextIssueBlocker = code == 'OCR_FAILED' || code == 'NOT_A_BILL';
            nextIssue = (stage != null && stage.isNotEmpty)
                ? '${stage.toUpperCase()}: $msg'
                : msg;
          }
        }
        setState(() {
          if (nextStage != null) _stage = nextStage;
          if (nextProg != null) _stageProgress = nextProg;
          if (nextIssue != null) {
            _scanIssue = nextIssue;
            _scanIssueBlocker = nextIssueBlocker;
          }
          _scan = res;
        });
      }

      final sw = Stopwatch()..start();
      await pollOnce();
      _pollTimer = Timer.periodic(const Duration(milliseconds: 450), (_) async {
        if (!mounted) return;
        if (!_busy) return;
        if (sw.elapsed > const Duration(seconds: 95)) {
          _pollTimer?.cancel();
          setState(() {
            _busy = false;
            _stage = _ScanStage.error;
            _error =
                'Scan timed out. Your connection may be unstable or the server is slow. Try again.';
          });
          return;
        }
        try {
          await pollOnce();
          final meta = _scan?['scan_meta'];
          final st = (meta is Map) ? meta['stage']?.toString() : null;
          if ((st ?? '').toString().trim().toLowerCase() == 'ready' ||
              (st ?? '').toString().trim().toLowerCase() == 'error') {
            _pollTimer?.cancel();
            final endedInError =
                (st ?? '').toString().trim().toLowerCase() == 'error';
            setState(() {
              _busy = false;
              _stage = endedInError ? _ScanStage.error : _ScanStage.done;
              if (endedInError && _error == null) {
                _error = _scanIssue ?? 'Scan failed. Please retry or retake the photo.';
              }
            });
            if (!endedInError) HapticFeedback.selectionClick();
          }
        } catch (e) {
          // Keep polling for transient errors; UI shows last good partial state.
          if (!mounted) return;
          setState(() => _scanIssue = friendlyApiError(e));
        }
      });
    } catch (e) {
      if (!mounted) return;
      if (e is DioException && shouldQueueScanOffline(e)) {
        final id = await OfflineStore.queueScanJob(
          businessId: session.primaryBusiness.id,
          jpegBytes: bytes,
        );
        setState(() {
          _busy = false;
          _stage = _ScanStage.error;
          _queuedScanId = id;
          _error =
              'Saved offline. We will retry when your connection is back. You can retry now.';
        });
        return;
      }
      setState(() {
        _busy = false;
        _stage = _ScanStage.error;
        _error = friendlyApiError(e);
      });
    } finally {
      _stageTimer?.cancel();
      // polling timer stays active on success until ready/error
    }
  }

  void _resetAll() {
    _stageTimer?.cancel();
    _pollTimer?.cancel();
    setState(() {
      _jpegBytes = null;
      _scan = null;
      _busy = false;
      _stage = _ScanStage.idle;
      _error = null;
      _scanIssue = null;
      _scanIssueBlocker = false;
      _queuedScanId = null;
    });
  }

  Future<void> _openPurchaseEntryFromScan() async {
    final s = _scan;
    if (s == null || _busy) return;
    final snap = Map<String, dynamic>.from(s);
    final token = snap['scan_token']?.toString().trim();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan token missing — try scanning again.')),
      );
      return;
    }
    ref.read(purchaseScanDraftMapProvider.notifier).setDraft(snap);
    final draft = purchaseDraftFromScanResultJson(snap);
    await context.push(
      '/purchase/new',
      extra: {
        'initialDraft': draft,
        'aiScan': {
          'token': token,
          'baseScan': snap,
        },
      },
    );
    if (!mounted) return;
    final latest = ref.read(purchaseScanDraftMapProvider);
    if (latest != null) {
      setState(() => _scan = Map<String, dynamic>.from(latest));
    }
  }

  String _confLabel(Object? v) {
    final d = (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '');
    if (d == null) return 'Needs review';
    if (d >= 0.92) return 'High';
    if (d >= 0.70) return 'Medium';
    return 'Needs review';
  }

  Color _confBg(Object? v) {
    final d = (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '');
    if (d == null) return const Color(0xFFFEF2F2);
    if (d >= 0.92) return const Color(0xFFECFDF3);
    if (d >= 0.70) return const Color(0xFFFFFBEB);
    return const Color(0xFFFEF2F2);
  }

  Color _confFg(Object? v) {
    final d = (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '');
    if (d == null) return const Color(0xFF991B1B);
    if (d >= 0.92) return const Color(0xFF027A48);
    if (d >= 0.70) return const Color(0xFFB45309);
    return const Color(0xFF991B1B);
  }

  Widget _confChip(Object? v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _confBg(v),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        _confLabel(v),
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: _confFg(v)),
      ),
    );
  }

  void _applyDirectoryCandidate(String key, Map<String, dynamic> cand) {
    final s = _scan;
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
    ref.read(purchaseScanDraftMapProvider.notifier).setDraft(Map<String, dynamic>.from(s));
    setState(() => _scan = Map<String, dynamic>.from(s));
  }

  Future<void> _editItemRow(int index, Map<String, dynamic> item) async {
    String? supplierId;
    final sup = _scan?['supplier'];
    if (sup is Map) {
      final raw = sup['matched_id']?.toString().trim();
      supplierId = (raw != null && raw.isNotEmpty) ? raw : null;
    }
    await editScanDraftItemRow(
      context,
      ref: ref,
      index: index,
      item: item,
      supplierMatchedId: supplierId,
      onSaved: (idx, next) {
        final s = _scan;
        if (s == null) return;
        final items = s['items'];
        if (items is! List || idx < 0 || idx >= items.length) return;
        items[idx] = next;
        ref.read(purchaseScanDraftMapProvider.notifier).setDraft(Map<String, dynamic>.from(s));
        setState(() => _scan = Map<String, dynamic>.from(s));
      },
    );
  }

  String _stageLabel(_ScanStage s) {
    // Vision-first wording only — no OCR-style labels in user-visible copy.
    return switch (s) {
      _ScanStage.idle => 'Upload a bill photo to begin.',
      _ScanStage.preparingImage => 'Preparing image…',
      _ScanStage.uploading => 'Uploading…',
      _ScanStage.extractingText => 'Reading bill (AI vision)…',
      _ScanStage.parsingItems => 'Extracting line items…',
      _ScanStage.matchingSuppliers => 'Matching supplier & catalog…',
      _ScanStage.validating => 'Checking amounts…',
      _ScanStage.readyForReview => 'Ready for your review…',
      _ScanStage.done => 'Review and match items before saving',
      _ScanStage.error => 'Needs attention',
    };
  }

  Widget _confidencePill(double c) {
    // Trader-friendly confidence bands (no numeric % UI).
    final (bg, fg, label) = c >= 0.85
        ? (const Color(0xFFECFDF5), const Color(0xFF065F46), 'HIGH')
        : (c >= 0.55
            ? (const Color(0xFFFFFBEB), const Color(0xFF92400E), 'MEDIUM')
            : (const Color(0xFFFEF2F2), const Color(0xFF991B1B), 'LOW'));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withAlpha(35)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _supplierBrokerSummary() {
    final s = _scan;
    if (s == null) return const SizedBox.shrink();
    final sup = s['supplier'];
    final bro = s['broker'];
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

    List<Map<String, dynamic>> candidatesOf(Object? x) {
      if (x is! Map) return const [];
      final c = x['candidates'];
      if (c is! List) return const [];
      final out = <Map<String, dynamic>>[];
      for (final e in c.take(3)) {
        if (e is Map) out.add(Map<String, dynamic>.from(e));
      }
      return out;
    }

    final supCands = candidatesOf(sup);
    final broCands = candidatesOf(bro);

    return Card(
      margin: const EdgeInsets.only(top: 12),
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
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      if (supCands.isNotEmpty && supConf() < 0.92) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (final c in supCands)
                              OutlinedButton(
                                onPressed: () => _applyDirectoryCandidate('supplier', c),
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
                _confidencePill(supConf()),
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
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      if (broCands.isNotEmpty && broConf() < 0.92) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (final c in broCands)
                              OutlinedButton(
                                onPressed: () => _applyDirectoryCandidate('broker', c),
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
                _confidencePill(broConf()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chargesSummary() {
    final s = _scan;
    if (s == null) return const SizedBox.shrink();
    final charges = s['charges'];
    if (charges is! Map) return const SizedBox.shrink();
    final ch = Map<String, dynamic>.from(charges);
    final delivered = ch['delivered_rate'];
    final billty = ch['billty_rate'];
    final freight = ch['freight_amount'];
    final paymentDaysRaw = s['payment_days'];
    final int? paymentDays = paymentDaysRaw is int
        ? paymentDaysRaw
        : (paymentDaysRaw is num ? paymentDaysRaw.round() : int.tryParse(paymentDaysRaw?.toString() ?? ''));
    final hasAny = delivered != null || billty != null || freight != null || paymentDays != null;
    if (!hasAny) return const SizedBox.shrink();

    String fmtMoney(Object? v) {
      if (v is num) return '₹${v.toStringAsFixed(0)}';
      return '—';
    }

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Detected charges', style: HexaDsType.formSectionLabel),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                if (freight is num) _chip('Freight', fmtMoney(freight)),
                if (delivered is num) _chip('Delivered', fmtMoney(delivered)),
                if (billty is num) _chip('Billty', fmtMoney(billty)),
                if (paymentDays != null) _chip('Payment', '$paymentDays days'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _warningsSummary() {
    final s = _scan;
    if (s == null) return const SizedBox.shrink();
    final warns = s['warnings'];
    if (warns is! List || warns.isEmpty) return const SizedBox.shrink();
    final first = warns.take(3).toList();
    return Card(
      margin: const EdgeInsets.only(top: 12),
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

  Widget _chip(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$k $v', style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }

  Widget _itemsTable() {
    final s = _scan;
    if (s == null) return const SizedBox.shrink();
    final items = s['items'];
    if (items is! List || items.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Could not confidently detect item rows. Try better lighting or crop the bill.'),
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _ScanTableHeader(),
            const SizedBox(height: 6),
            for (var i = 0; i < items.length; i++)
              if (items[i] is Map)
                _ScanTableRow(
                  item: Map<String, dynamic>.from(items[i] as Map),
                  onTap: () => _editItemRow(i, Map<String, dynamic>.from(items[i] as Map)),
                  trailing: _confChip((items[i] as Map)['confidence']),
                ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final bytes = _jpegBytes;
    final hasImage = bytes != null && bytes.isNotEmpty;
    final hasResult = _scan != null;
    final isWorking = _busy;
    final pendingOffline = session != null &&
        OfflineStore.getPendingScanJobs(session.primaryBusiness.id).isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Scan purchase bill')),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Scan purchase bill', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text(
                'Camera or gallery only here. AI reads the bill; then tap Continue to open purchase entry to match '
                'supplier and lines — nothing is saved until you confirm there.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Malayalam + English supported · Handwriting supported',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: isWorking ? null : () => _pick(ImageSource.camera),
                              icon: const Icon(Icons.photo_camera_rounded),
                              label: const Text('Camera'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: isWorking ? null : () => _pick(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library_rounded),
                              label: const Text('Gallery'),
                            ),
                          ),
                        ],
                      ),
                      if (pendingOffline) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: isWorking ? null : _loadFirstQueuedScanAndStart,
                            icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                            label: const Text('Resume saved offline scan'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (hasImage) ...[
                const SizedBox(height: 12),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: InteractiveViewer(
                          minScale: 0.8,
                          maxScale: 4,
                          child: Image.memory(
                            Uint8List.fromList(bytes),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      if (_busy && _stageProgress > 0)
                        LinearProgressIndicator(value: _stageProgress.clamp(0.05, 1.0)),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _stageLabel(_stage),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (_busy)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: const Color(0xFFFEF2F2),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFF991B1B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
              if (_scanIssue != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: _scanIssueBlocker
                      ? const Color(0xFFFEF2F2)
                      : const Color(0xFFFFFBEB),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _scanIssue!,
                      style: TextStyle(
                        color: _scanIssueBlocker
                            ? const Color(0xFF991B1B)
                            : const Color(0xFF92400E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
              if (hasResult) ...[
                _supplierBrokerSummary(),
                _chargesSummary(),
                _warningsSummary(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('Detected items', style: HexaDsType.formSectionLabel),
                    const Spacer(),
                    Text(
                      'Tap row to edit',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.black54),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _itemsTable(),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isWorking
                      ? null
                      : (hasResult
                          ? _resetAll
                          : (hasImage ? _scanNow : null)),
                  icon: Icon(hasResult ? Icons.refresh_rounded : Icons.document_scanner_rounded),
                  label: Text(
                    hasResult ? 'Retake' : (_busy ? 'Scanning…' : 'Scan'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (!isWorking && hasResult)
                      ? () {
                          if (_scroll.hasClients) {
                            _scroll.animateTo(
                              _scroll.position.maxScrollExtent * 0.35,
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        }
                      : null,
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('Review'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (!isWorking && hasResult) ? _openPurchaseEntryFromScan : null,
                  icon: const Icon(Icons.fact_check_rounded),
                  label: const Text('Continue'),
                  style: FilledButton.styleFrom(
                    backgroundColor: HexaColors.brandPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanTableHeader extends StatelessWidget {
  const _ScanTableHeader();

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: Colors.black54,
        );
    return Row(
      children: [
        Expanded(flex: 6, child: Text('Item', style: s)),
        Expanded(flex: 2, child: Text('Qty', style: s, textAlign: TextAlign.right)),
        Expanded(flex: 2, child: Text('Unit', style: s, textAlign: TextAlign.center)),
        Expanded(flex: 2, child: Text('P', style: s, textAlign: TextAlign.right)),
        Expanded(flex: 2, child: Text('S', style: s, textAlign: TextAlign.right)),
      ],
    );
  }
}

class _ScanTableRow extends StatelessWidget {
  const _ScanTableRow({required this.item, required this.onTap, required this.trailing});
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final Widget trailing;

  String _s(Object? v, [String fallback = '—']) {
    final t = v?.toString().trim() ?? '';
    return t.isEmpty ? fallback : t;
  }

  String _n(Object? v) {
    if (v is num) return (v == v.roundToDouble()) ? '${v.round()}' : v.toStringAsFixed(2);
    final t = v?.toString().trim() ?? '';
    return t.isEmpty ? '—' : t;
  }

  @override
  Widget build(BuildContext context) {
    final name = _s(item['matched_name'] ?? item['raw_name']);
    final qty = _n(item['bags'] ?? item['qty']);
    final unit = _s(item['unit_type'], '—').toLowerCase();
    final p = _n(item['purchase_rate']);
    final s = _n(item['selling_rate']);
    final conf = item['confidence'];
    final c = (conf is num) ? conf.toDouble() : double.tryParse(conf?.toString() ?? '');
    final matched = (item['matched_catalog_item_id'] ?? item['matched_id'])?.toString().trim();
    final hasMatch = matched != null && matched.isNotEmpty;
    final hasRate = (item['purchase_rate'] is num) ||
        (double.tryParse(item['purchase_rate']?.toString() ?? '') != null);
    final needsReview = (c == null || c < 0.70) || !hasMatch || !hasRate;
    final bg = !needsReview
        ? Colors.transparent
        : (c != null && c >= 0.70 ? const Color(0xFFFFFBEB) : const Color(0xFFFEF2F2));
    final border = !needsReview
        ? Colors.transparent
        : (c != null && c >= 0.70 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border(left: BorderSide(color: border, width: needsReview ? 3 : 0)),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Row(
          children: [
            Expanded(
              flex: 6,
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(flex: 2, child: Text(qty, textAlign: TextAlign.right)),
            Expanded(flex: 2, child: Text(unit, textAlign: TextAlign.center)),
            Expanded(flex: 2, child: Text(p, textAlign: TextAlign.right)),
            Expanded(flex: 2, child: Text(s, textAlign: TextAlign.right)),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}
