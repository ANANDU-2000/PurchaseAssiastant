import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/navigation_ext.dart';
import '../mapping/ai_scan_purchase_draft_map.dart';
import 'purchase_scan_draft_map_provider.dart';

/// Legacy `/purchase/scan-draft` route — forwards to the main purchase wizard with AI scan session.
class PurchaseScanDraftWizardPage extends ConsumerStatefulWidget {
  const PurchaseScanDraftWizardPage({super.key});

  @override
  ConsumerState<PurchaseScanDraftWizardPage> createState() =>
      _PurchaseScanDraftWizardPageState();
}

class _PurchaseScanDraftWizardPageState
    extends ConsumerState<PurchaseScanDraftWizardPage> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _redirect());
  }

  void _redirect() {
    if (_started || !mounted) return;
    _started = true;
    final snap = ref.read(purchaseScanDraftMapProvider);
    if (snap == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No scan data. Go back and scan again.')),
      );
      context.popOrGo('/purchase/scan');
      return;
    }
    final token = snap['scan_token']?.toString().trim();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan token missing — try scanning again.')),
      );
      context.popOrGo('/purchase/scan');
      return;
    }
    final draft = purchaseDraftFromScanResultJson(Map<String, dynamic>.from(snap));
    ref.read(purchaseScanDraftMapProvider.notifier).clear();
    if (!mounted) return;
    context.pushReplacement(
      '/purchase/new',
      extra: {
        'initialDraft': draft,
        'aiScan': {
          'token': token,
          'baseScan': Map<String, dynamic>.from(snap),
        },
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
