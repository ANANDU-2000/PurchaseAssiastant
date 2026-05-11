import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/router/navigation_ext.dart';

/// Download trade purchase backup as ZIP (CSV inside).
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  String _preset = 'month';
  bool _busy = false;

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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nothing to export for this range.')),
          );
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
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/settings'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Export trade purchases as a ZIP file containing purchases.csv. '
            'Use this for your own records or spreadsheets.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Text('Date range', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'month', label: Text('This month')),
              ButtonSegment(value: 'quarter', label: Text('90 days')),
              ButtonSegment(value: 'all', label: Text('All')),
            ],
            selected: {_preset},
            onSelectionChanged: (s) =>
                setState(() => _preset = s.first),
          ),
          const SizedBox(height: 24),
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
        ],
      ),
    );
  }
}
