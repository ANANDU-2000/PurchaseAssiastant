import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/utils/snack.dart';

const _kLastZipBackupKey = 'backup_last_zip_at';

/// Download trade purchase backup as ZIP from the server.
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  String _preset = 'month';
  bool _busy = false;
  DateTime? _lastBackupAt;

  @override
  void initState() {
    super.initState();
    _loadLastBackup();
  }

  Future<void> _loadLastBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_kLastZipBackupKey);
    if (ms == null || !mounted) return;
    setState(() => _lastBackupAt = DateTime.fromMillisecondsSinceEpoch(ms));
  }

  Future<void> _recordBackup() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastZipBackupKey, now.millisecondsSinceEpoch);
    if (mounted) setState(() => _lastBackupAt = now);
  }

  Future<void> _download() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() => _busy = true);
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
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/zip',
            name: fn,
          ),
        ],
        text: 'Purchase Assistant backup',
      );
      await _recordBackup();
    } on DioException catch (e) {
      if (mounted) {
        showTopSnack(context, friendlyApiError(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final lastLabel = _lastBackupAt == null
        ? 'No ZIP backup recorded on this device yet'
        : 'Last ZIP on this device: ${DateFormat('dd MMM yyyy, HH:mm').format(_lastBackupAt!)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup & export'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/settings'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Keep a copy of trade purchases offline. ZIP exports are built on the server; PDF statements live under Reports.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 12),
          Material(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 20, color: cs.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      lastLabel,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('ZIP — trade purchases',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('Period', style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
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
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _download,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(_busy ? 'Preparing…' : 'Download ZIP'),
          ),
          const SizedBox(height: 28),
          Text('PDF statements',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            'Spend overview, item ledgers, and purchase statements are exported as PDF from their screens.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 12),
          _ExportRow(
            icon: Icons.bar_chart_rounded,
            title: 'Reports overview',
            subtitle: 'Charts and spend breakdown',
            onTap: () => context.push('/reports'),
          ),
          _ExportRow(
            icon: Icons.receipt_long_outlined,
            title: 'Purchase history',
            subtitle: 'Filter and open any bill',
            onTap: () => context.push('/purchase'),
          ),
        ],
      ),
    );
  }
}

class _ExportRow extends StatelessWidget {
  const _ExportRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          leading: Icon(icon, color: const Color(0xFF17A8A7)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      ),
    );
  }
}
