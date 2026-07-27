import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/resolve_catalog_item_id.dart';
import 'reports_item_detail_page.dart';

/// Resolves report item name → catalog detail when possible.
class ReportsItemRedirectPage extends ConsumerStatefulWidget {
  const ReportsItemRedirectPage({
    super.key,
    required this.itemKey,
    required this.itemName,
  });

  final String itemKey;
  final String itemName;

  @override
  ConsumerState<ReportsItemRedirectPage> createState() =>
      _ReportsItemRedirectPageState();
}

class _ReportsItemRedirectPageState extends ConsumerState<ReportsItemRedirectPage> {
  bool _resolved = false;
  bool _useFallback = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _redirect());
  }

  Future<void> _redirect() async {
    if (_resolved) return;
    final id = await resolveCatalogItemId(
      ref,
      itemName: widget.itemName,
    );
    if (!mounted) return;
    _resolved = true;
    if (id != null && id.isNotEmpty) {
      context.replace('/catalog/item/$id?tab=purchases&source=reports');
      return;
    }
    setState(() => _useFallback = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolved || !_useFallback) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return ReportsItemDetailPage(
      itemKey: widget.itemKey,
      itemName: widget.itemName,
    );
  }
}
