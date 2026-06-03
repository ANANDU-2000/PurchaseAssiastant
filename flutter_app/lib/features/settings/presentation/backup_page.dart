import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/services/backup_export_io.dart';
import '../../../core/utils/snack.dart';

const _kLastZipBackupKey = 'backup_last_zip_at';
const _kLastStockXlsxKey = 'backup_last_stock_xlsx_at';
const _kLastPurchasesPdfKey = 'backup_last_purchases_pdf_at';

/// Owner export hub: stock Excel, monthly purchases PDF, ZIP trade backup.
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  String _preset = 'month';
  bool _busyZip = false;
  bool _busyStock = false;
  bool _busyPdf = false;
  DateTime? _lastZipAt;
  DateTime? _lastStockAt;
  DateTime? _lastPdfAt;

  @override
  void initState() {
    super.initState();
    _loadTimestamps();
  }

  Future<void> _loadTimestamps() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _lastZipAt = _ts(prefs.getInt(_kLastZipBackupKey));
      _lastStockAt = _ts(prefs.getInt(_kLastStockXlsxKey));
      _lastPdfAt = _ts(prefs.getInt(_kLastPurchasesPdfKey));
    });
  }

  DateTime? _ts(int? ms) =>
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);

  Future<void> _record(String key) async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, now.millisecondsSinceEpoch);
    if (!mounted) return;
    setState(() {
      if (key == _kLastZipBackupKey) _lastZipAt = now;
      if (key == _kLastStockXlsxKey) _lastStockAt = now;
      if (key == _kLastPurchasesPdfKey) _lastPdfAt = now;
    });
  }

  Future<void> _shareBytes({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    required String shareText,
    required String saveCategory,
  }) async {
    await saveBackupExportBytes(
      bytes: bytes,
      filename: filename,
      category: saveCategory,
    );
    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: mimeType, name: filename)],
      text: shareText,
    );
  }

  Future<void> _downloadStockExcel() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() => _busyStock = true);
    try {
      final bytes = await ref.read(hexaApiProvider).downloadStockInventoryXlsx(
            businessId: session.primaryBusiness.id,
          );
      if (bytes.isEmpty) {
        if (mounted) {
          showTopSnack(context, 'No stock items to export.', isError: true);
        }
        return;
      }
      final day = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await _shareBytes(
        bytes: bytes,
        filename: 'harisree_stock_$day.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        shareText: 'Harisree stock inventory',
        saveCategory: 'stock',
      );
      await _record(_kLastStockXlsxKey);
    } on DioException catch (e) {
      if (mounted) showTopSnack(context, friendlyApiError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyStock = false);
    }
  }

  Future<void> _downloadPurchasesPdf() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() => _busyPdf = true);
    try {
      final bytes = await ref.read(hexaApiProvider).downloadPurchasesMonthPdf(
            businessId: session.primaryBusiness.id,
          );
      if (bytes.isEmpty) {
        if (mounted) {
          showTopSnack(
            context,
            'No purchases this month to export.',
            isError: true,
          );
        }
        return;
      }
      final now = DateTime.now();
      final fn =
          'harisree_purchases_${now.year}-${now.month.toString().padLeft(2, '0')}.pdf';
      await _shareBytes(
        bytes: bytes,
        filename: fn,
        mimeType: 'application/pdf',
        shareText: 'Harisree purchases — this month',
        saveCategory: 'purchases',
      );
      await _record(_kLastPurchasesPdfKey);
    } on DioException catch (e) {
      if (mounted) showTopSnack(context, friendlyApiError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyPdf = false);
    }
  }

  Future<void> _downloadZip() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() => _busyZip = true);
    try {
      final bytes = await ref.read(hexaApiProvider).downloadBusinessBackup(
            businessId: session.primaryBusiness.id,
            rangePreset: _preset,
          );
      if (bytes.isEmpty) {
        if (mounted) {
          showTopSnack(context, 'Nothing to export for this range.', isError: true);
        }
        return;
      }
      final day = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final fn = 'purchase_assistant_backup_$day.zip';
      await saveBackupExportBytes(
        bytes: bytes,
        filename: fn,
        category: 'zip',
      );
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/zip',
            name: fn,
          ),
        ],
        text: 'Harisree trade purchase backup',
      );
      await _record(_kLastZipBackupKey);
    } on DioException catch (e) {
      if (mounted) showTopSnack(context, friendlyApiError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyZip = false);
    }
  }

  String _fmt(DateTime? t) =>
      t == null ? 'Never on this device' : DateFormat('dd MMM yyyy, HH:mm').format(t);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final monthLabel = DateFormat('MMMM yyyy').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Export & Backup'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/settings'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Download reports for your records. On phone, files are also saved under '
            'warehouse_exports in app storage when possible.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 20),
          Text('Export & Backup',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busyStock ? null : _downloadStockExcel,
            icon: _busyStock
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.table_chart_outlined),
            label: Text(_busyStock ? 'Preparing…' : 'Download Stock Excel'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Last: ${_fmt(_lastStockAt)}',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _busyPdf ? null : _downloadPurchasesPdf,
            icon: _busyPdf
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            label: Text(
              _busyPdf
                  ? 'Preparing…'
                  : 'Download Purchases PDF (this month)',
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              '$monthLabel · Last: ${_fmt(_lastPdfAt)}',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 28),
          Text('ZIP — trade purchases (CSV)',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('This month'),
                selected: _preset == 'month',
                onSelected: (_) => setState(() => _preset = 'month'),
              ),
              ChoiceChip(
                label: const Text('90 days'),
                selected: _preset == 'quarter',
                onSelected: (_) => setState(() => _preset = 'quarter'),
              ),
              ChoiceChip(
                label: const Text('All'),
                selected: _preset == 'all',
                onSelected: (_) => setState(() => _preset = 'all'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busyZip ? null : _downloadZip,
            icon: _busyZip
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_zip_outlined),
            label: Text(_busyZip ? 'Preparing…' : 'Download ZIP backup'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Last ZIP: ${_fmt(_lastZipAt)}',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
