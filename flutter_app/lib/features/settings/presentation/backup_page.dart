import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/design_system/widgets/app_button.dart';
import '../../../core/design_system/widgets/app_text_field.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/services/backup_auto_service.dart';
import '../../../core/services/backup_deliver.dart';
import '../../../core/services/prefs_helper.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../../../core/utils/snack.dart';
import '../../../shared/widgets/desktop_page_shell.dart';

const _kLastZipBackupKey = 'backup_last_zip_at';
const _kLastJsonBackupKey = 'backup_last_json_at';
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
  bool _busyJson = false;
  bool _busyStock = false;
  bool _busyPdf = false;
  bool _busyServer = false;
  bool _busyDryRun = false;
  DateTime? _lastZipAt;
  DateTime? _lastJsonAt;
  DateTime? _lastStockAt;
  DateTime? _lastPdfAt;
  bool _autoDaily = false;
  List<dynamic> _backupLogs = [];
  Map<String, dynamic>? _dryRunResult;

  @override
  void initState() {
    super.initState();
    _loadTimestamps();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBackupLogs());
  }

  Future<void> _loadTimestamps() async {
    final prefs = PrefsHelper.prefs;
    if (!mounted) return;
    setState(() {
      _lastZipAt = _ts(prefs.getInt(_kLastZipBackupKey));
      _lastJsonAt = _ts(prefs.getInt(_kLastJsonBackupKey));
      _lastStockAt = _ts(prefs.getInt(_kLastStockXlsxKey));
      _lastPdfAt = _ts(prefs.getInt(_kLastPurchasesPdfKey));
      _autoDaily = prefs.getBool(kAutoDailyBackupEnabledKey) ?? false;
    });
  }

  DateTime? _ts(int? ms) =>
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);

  Future<void> _record(String key) async {
    final now = DateTime.now();
    final prefs = PrefsHelper.prefs;
    await prefs.setInt(key, now.millisecondsSinceEpoch);
    if (!mounted) return;
    setState(() {
      if (key == _kLastZipBackupKey) _lastZipAt = now;
      if (key == _kLastJsonBackupKey) _lastJsonAt = now;
      if (key == _kLastStockXlsxKey) _lastStockAt = now;
      if (key == _kLastPurchasesPdfKey) _lastPdfAt = now;
    });
  }

  String? _sessionBlockedMessage() {
    if (ref.read(sessionProvider) == null) {
      return 'Sign in to download exports.';
    }
    return null;
  }

  Future<bool> _ensureFreshSession() async {
    try {
      await ref.read(sessionProvider.notifier).ensureFreshSessionForExport();
      return true;
    } catch (_) {
      if (!mounted) return false;
      showTopSnack(
        context,
        'Your session expired. Please sign out and sign in again.',
        isError: true,
      );
      return false;
    }
  }

  Future<void> _deliverAndRecord({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    required String shareText,
    required String saveCategory,
    required String recordKey,
  }) async {
    final result = await deliverBackupFile(
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
      shareText: shareText,
      saveCategory: saveCategory,
    );
    if (!mounted) return;
    if (result.ok) {
      await _record(recordKey);
      showTopSnack(context, result.message);
    } else {
      showTopSnack(context, result.message, isError: true);
    }
  }

  Future<void> _downloadStockExcel() async {
    final blocked = _sessionBlockedMessage();
    if (blocked != null) {
      showTopSnack(context, blocked, isError: true);
      return;
    }
    if (!await _ensureFreshSession()) return;
    final session = ref.read(sessionProvider)!;
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
      await _deliverAndRecord(
        bytes: bytes,
        filename: 'harisree_stock_$day.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        shareText: 'Harisree stock inventory',
        saveCategory: 'stock',
        recordKey: _kLastStockXlsxKey,
      );
    } on DioException catch (e) {
      if (mounted) showTopSnack(context, friendlyApiError(e), isError: true);
    } catch (_) {
      if (mounted) {
        showTopSnack(
          context,
          'Stock export failed. Sign in again or try later.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busyStock = false);
    }
  }

  Future<void> _downloadPurchasesPdf() async {
    final blocked = _sessionBlockedMessage();
    if (blocked != null) {
      showTopSnack(context, blocked, isError: true);
      return;
    }
    if (!await _ensureFreshSession()) return;
    final session = ref.read(sessionProvider)!;
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
      await _deliverAndRecord(
        bytes: bytes,
        filename: fn,
        mimeType: 'application/pdf',
        shareText: 'Harisree purchases — this month',
        saveCategory: 'purchases',
        recordKey: _kLastPurchasesPdfKey,
      );
    } on DioException catch (e) {
      if (mounted) {
        if (e.response?.statusCode == 404) {
          showTopSnack(
            context,
            'No purchases this month to export. Stock-committed bills are included once saved.',
            isError: true,
          );
        } else {
          showTopSnack(context, friendlyApiError(e), isError: true);
        }
      }
    } catch (_) {
      if (mounted) {
        showTopSnack(
          context,
          'PDF export failed. Sign in again or try later.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busyPdf = false);
    }
  }

  Future<void> _downloadJson() async {
    final blocked = _sessionBlockedMessage();
    if (blocked != null) {
      showTopSnack(context, blocked, isError: true);
      return;
    }
    if (!await _ensureFreshSession()) return;
    final session = ref.read(sessionProvider)!;
    setState(() => _busyJson = true);
    try {
      final bytes = await ref.read(hexaApiProvider).downloadBusinessBackupJson(
            businessId: session.primaryBusiness.id,
          );
      if (bytes.isEmpty) {
        if (mounted) {
          showTopSnack(context, 'Nothing to export.', isError: true);
        }
        return;
      }
      final day = DateFormat('yyyyMMdd').format(DateTime.now());
      await _deliverAndRecord(
        bytes: bytes,
        filename: 'harisree_backup_$day.json',
        mimeType: 'application/json',
        shareText: 'Harisree JSON backup',
        saveCategory: 'json',
        recordKey: _kLastJsonBackupKey,
      );
    } on DioException catch (e) {
      if (mounted) showTopSnack(context, friendlyApiError(e), isError: true);
    } catch (_) {
      if (mounted) {
        showTopSnack(
          context,
          'JSON backup failed. Sign in again or try later.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busyJson = false);
    }
  }

  Future<void> _downloadZip() async {
    final blocked = _sessionBlockedMessage();
    if (blocked != null) {
      showTopSnack(context, blocked, isError: true);
      return;
    }
    if (!await _ensureFreshSession()) return;
    final session = ref.read(sessionProvider)!;
    setState(() => _busyZip = true);
    try {
      final bytes = await ref.read(hexaApiProvider).downloadBusinessBackup(
            businessId: session.primaryBusiness.id,
            rangePreset: _preset,
          );
      if (bytes.isEmpty) {
        if (mounted) {
          showTopSnack(context, 'Nothing to export for this range.',
              isError: true);
        }
        return;
      }
      final day = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await _deliverAndRecord(
        bytes: bytes,
        filename: 'purchase_assistant_backup_$day.zip',
        mimeType: 'application/zip',
        shareText: 'Harisree trade purchase backup',
        saveCategory: 'zip',
        recordKey: _kLastZipBackupKey,
      );
    } on DioException catch (e) {
      if (mounted) showTopSnack(context, friendlyApiError(e), isError: true);
    } catch (_) {
      if (mounted) {
        showTopSnack(
          context,
          'ZIP backup failed. Sign in again or try later.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busyZip = false);
    }
  }

  String _fmt(DateTime? t) =>
      t == null ? 'Never on this device' : DateFormat('dd MMM yyyy, HH:mm').format(t);

  bool get _anyBusy =>
      _busyZip || _busyJson || _busyStock || _busyPdf || _busyServer || _busyDryRun;

  Future<void> _loadBackupLogs() async {
    final bid = ref.read(sessionProvider)?.primaryBusiness.id;
    if (bid == null || bid.isEmpty) return;
    try {
      final data =
          await ref.read(hexaApiProvider).listBackupLogs(businessId: bid);
      if (!mounted) return;
      setState(() => _backupLogs = (data['items'] as List?) ?? []);
    } catch (_) {
      // Non-blocking — export page still works for client downloads.
    }
  }

  Future<void> _runServerBackup() async {
    final bid = ref.read(sessionProvider)?.primaryBusiness.id;
    if (bid == null) return;
    setState(() => _busyServer = true);
    try {
      final out =
          await ref.read(hexaApiProvider).runServerBackup(businessId: bid);
      if (!mounted) return;
      showTopSnack(
        context,
        'Server backup ${out['status'] ?? 'done'}'
        '${out['size_bytes'] != null ? ' · ${out['size_bytes']} B' : ''}',
      );
      await _loadBackupLogs();
    } on DioException catch (e) {
      if (mounted) showTopSnack(context, friendlyApiError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyServer = false);
    }
  }

  Future<void> _dryRunRestore() async {
    final bid = ref.read(sessionProvider)?.primaryBusiness.id;
    if (bid == null) return;
    final ctrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore dry-run'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(ctx).width * 0.9,
            ),
            child: AppTextField(
              controller: ctrl,
              maxLines: 12,
              label: 'Paste backup JSON here (never commits)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Validate'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      Map<String, dynamic> payload;
      try {
        final decoded = jsonDecode(ctrl.text);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('JSON root must be an object');
        }
        payload = decoded;
      } catch (_) {
        showTopSnack(context, 'Invalid JSON', isError: true);
        return;
      }
      setState(() => _busyDryRun = true);
      try {
        final out = await ref.read(hexaApiProvider).restoreDryRun(
              businessId: bid,
              payload: payload,
            );
        if (!mounted) return;
        setState(() => _dryRunResult = out);
        showTopSnack(
          context,
          out['ok'] == true ? 'Dry-run passed' : 'Dry-run failed',
          isError: out['ok'] != true,
        );
      } on DioException catch (e) {
        if (mounted) showTopSnack(context, friendlyApiError(e), isError: true);
      } finally {
        if (mounted) setState(() => _busyDryRun = false);
      }
    } finally {
      ctrl.dispose();
    }
  }

  String get _storageHint {
    if (kIsWeb) {
      return 'On web, files download to your browser Downloads folder. '
          'Allow downloads for this site.';
    }
    return 'Manual exports open the share sheet — save the file to any folder, '
        'send via WhatsApp, or store in Google Drive.';
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final monthLabel = DateFormat('MMMM yyyy').format(DateTime.now());
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;

    final body = ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          _storageHint,
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
        ),
        const SizedBox(height: 24),

        // ── Export Data ──
        _ZoneHeader('Export Data'),
        Text(
          'Download reports for your records.',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
        ),
        const SizedBox(height: 12),
        _ExportCard(
          children: [
            ListTile(
              leading: Icon(Icons.table_chart_outlined, color: cs.primary),
              title: const Text('Stock Excel'),
              subtitle: Text(
                'Last: ${_fmt(_lastStockAt)}',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              trailing: _busyStock
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.picture_as_pdf_outlined, color: cs.primary),
              title: const Text('Purchases PDF'),
              subtitle: Text(
                '$monthLabel · Last: ${_fmt(_lastPdfAt)}',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              trailing: _busyPdf
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.data_object_outlined, color: cs.primary),
              title: const Text('JSON backup'),
              subtitle: Text(
                'Catalog, suppliers, 90-day purchases, stock audit · Last: ${_fmt(_lastJsonAt)}',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              trailing: _busyJson
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AppPrimaryButton(
              label: _busyStock ? 'Preparing…' : 'Download Stock Excel',
              loading: _busyStock,
              enabled: !_anyBusy || _busyStock,
              onPressed: _downloadStockExcel,
            ),
            AppSecondaryButton(
              label: _busyPdf ? 'Preparing…' : 'Download Purchases PDF',
              loading: _busyPdf,
              enabled: !_anyBusy || _busyPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              onPressed: _downloadPurchasesPdf,
            ),
            AppSecondaryButton(
              label: _busyJson ? 'Preparing…' : 'Download JSON',
              loading: _busyJson,
              enabled: !_anyBusy || _busyJson,
              icon: const Icon(Icons.data_object_outlined, size: 18),
              onPressed: _downloadJson,
            ),
          ],
        ),

        const SizedBox(height: 28),

        // ── Full Backup ──
        if (!kIsWeb) ...[
          _ZoneHeader('Full Backup'),
          Text(
            'ZIP contains purchase summary PDF, one PDF per bill, supplier ledger PDFs, and stock Excel.',
            style:
                tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 12),
          _ExportCard(
            children: [
              ListTile(
                leading: Icon(Icons.folder_zip_outlined, color: cs.primary),
                title: const Text('ZIP backup'),
                subtitle: Text(
                  'Last: ${_fmt(_lastZipAt)}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                trailing: _busyZip
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
            ],
          ),
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
          const SizedBox(height: 8),
          AppSecondaryButton(
            label: _busyZip ? 'Preparing…' : 'Download ZIP backup',
            loading: _busyZip,
            enabled: !_anyBusy || _busyZip,
            icon: const Icon(Icons.folder_zip_outlined, size: 18),
            onPressed: _downloadZip,
          ),
          const SizedBox(height: 28),
        ],

        // ── Automatic Backup ──
        _ZoneHeader('Automatic Backup'),
        Text(
          kIsWeb
              ? 'Once per day when you open the app: JSON backup → browser Downloads'
              : 'Once per day when you open the app: ZIP (PDFs + stock Excel) '
                  'and monthly purchases PDF → Downloads/HarisreeWarehouse',
          style:
              tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
        ),
        const SizedBox(height: 12),
        _ExportCard(
          children: [
            SwitchListTile(
              secondary: Icon(
                Icons.autorenew_rounded,
                color: _autoDaily ? cs.primary : cs.onSurfaceVariant,
              ),
              title: Text(kIsWeb ? 'Daily auto-backup (web)' : 'Daily auto-backup'),
              subtitle: Text(
                _autoDaily ? 'Enabled — runs once daily when app opens' : 'Disabled',
                style: tt.bodySmall?.copyWith(
                  color: _autoDaily ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              value: _autoDaily,
              onChanged: _anyBusy
                  ? null
                  : (v) async {
                      final prefs = PrefsHelper.prefs;
                      await prefs.setBool(kAutoDailyBackupEnabledKey, v);
                      if (!mounted) return;
                      setState(() => _autoDaily = v);
                      if (v) {
                        unawaited(maybeRunDailyAutoBackup(ref));
                        showTopSnack(
                          context,
                          'Auto-backup enabled — runs once daily when the app opens.',
                        );
                      }
                    },
            ),
          ],
        ),

        const SizedBox(height: 28),

        // ── Server Backup ──
        _ZoneHeader('Server Backup'),
        Text(
          'Nightly JSON on the API host. Credentials are never included. '
          'Restore commit stays blocked until production-copy sign-off — dry-run only.',
          style:
              tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
        ),
        const SizedBox(height: 12),
        _ExportCard(
          children: [
            if (_backupLogs.isNotEmpty)
              for (final log in _backupLogs.take(5))
                if (log is Map)
                  ListTile(
                    dense: true,
                    title: Text(
                      '${log['run_type'] ?? '—'} · ${log['status'] ?? '—'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${log['created_at'] ?? ''}'
                      '${log['size_bytes'] != null ? ' · ${log['size_bytes']} B' : ''}',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
            if (_backupLogs.isEmpty)
              ListTile(
                leading: Icon(Icons.cloud_done_outlined, color: cs.onSurfaceVariant),
                title: const Text('No backup logs yet'),
                subtitle: Text(
                  'Run a server backup to see history here.',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AppSecondaryButton(
              label: _busyServer ? 'Running…' : 'Run server backup now',
              loading: _busyServer,
              enabled: !_anyBusy || _busyServer,
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              onPressed: _runServerBackup,
            ),
            AppSecondaryButton(
              label: 'Refresh logs',
              enabled: !_anyBusy,
              icon: const Icon(Icons.history, size: 18),
              onPressed: _loadBackupLogs,
            ),
          ],
        ),

        const SizedBox(height: 28),

        // ── Restore ──
        _ZoneHeader('Restore'),
        Text(
          'Dry-run to preview changes before restoring. Paste a backup JSON — nothing is committed.',
          style:
              tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
        ),
        const SizedBox(height: 12),
        _ExportCard(
          children: [
            ListTile(
              leading: Icon(Icons.rule_folder_outlined, color: cs.primary),
              title: const Text('Restore dry-run'),
              subtitle: _dryRunResult != null
                  ? Text(
                      _dryRunResult!['ok'] == true
                          ? 'Last dry-run: OK — would add: ${_dryRunResult!['would_add']}'
                          : 'Last dry-run: Failed — ${_dryRunResult!['error'] ?? 'unknown'}',
                      style: tt.bodySmall?.copyWith(
                        color: _dryRunResult!['ok'] == true
                            ? cs.primary
                            : cs.error,
                      ),
                    )
                  : Text(
                      'Validate a backup JSON without committing changes.',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
              trailing: _busyDryRun
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        AppSecondaryButton(
          label: _busyDryRun ? 'Validating…' : 'Run dry-run restore',
          loading: _busyDryRun,
          enabled: !_anyBusy || _busyDryRun,
          icon: const Icon(Icons.rule_folder_outlined, size: 18),
          onPressed: _dryRunRestore,
        ),
      ],
    );

    return Scaffold(
      backgroundColor: context.adaptiveScaffold,
      appBar: AppBar(
        backgroundColor: context.adaptiveAppBarBg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Export & Backup'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/settings'),
        ),
      ),
      body: isDesktop
          ? DesktopPageShell(
              maxContentWidth: HexaResponsive.maxFormWidth,
              padding: EdgeInsets.zero,
              child: body,
            )
          : body,
    );
  }
}

class _ZoneHeader extends StatelessWidget {
  const _ZoneHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: context.adaptiveCard,
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
