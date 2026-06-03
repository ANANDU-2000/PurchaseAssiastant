import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kBackupBannerDismissedYm = 'backup_banner_dismissed_ym';

/// Owner reminder: download local copies monthly (dismissible per calendar month).
class BackupMonthlyBanner extends StatefulWidget {
  const BackupMonthlyBanner({super.key});

  @override
  State<BackupMonthlyBanner> createState() => _BackupMonthlyBannerState();
}

class _BackupMonthlyBannerState extends State<BackupMonthlyBanner> {
  bool _visible = false;
  bool _loaded = false;

  static String _yearMonth(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final ym = _yearMonth(DateTime.now());
    final dismissed = prefs.getString(_kBackupBannerDismissedYm);
    if (mounted) {
      setState(() {
        _visible = dismissed != ym;
        _loaded = true;
      });
    }
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBackupBannerDismissedYm, _yearMonth(DateTime.now()));
    if (mounted) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || !_visible) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cs.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.cloud_download_outlined, color: cs.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Back up your data',
                      style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Download stock and purchase reports to keep a local copy.',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => context.push('/settings/backup'),
                      child: const Text('Export & Backup'),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss until next month',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: _dismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
