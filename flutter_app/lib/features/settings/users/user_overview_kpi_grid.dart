import 'package:flutter/material.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/design_system/hexa_responsive.dart';

class UserOverviewKpiGrid extends StatelessWidget {
  const UserOverviewKpiGrid({super.key, required this.user});

  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    final totals = user['stats'] is Map
        ? Map<String, dynamic>.from(user['stats'] as Map)
        : <String, dynamic>{};
    final desktop = context.isDesktopLayout;
    final cols = desktop ? 4 : 2;

    final metrics = [
      _Metric('Purchases', '${totals['purchases_total'] ?? 0}'),
      _Metric('Stock updates', '${totals['stock_edits_total'] ?? 0}'),
      _Metric('Items created', '${totals['items_created_total'] ?? 0}'),
      _Metric('Scans', '${totals['scans_total'] ?? 0}'),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: desktop ? 1.6 : 1.45,
      ),
      itemCount: metrics.length,
      itemBuilder: (context, i) {
        final m = metrics[i];
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(m.label, style: HexaDsType.labelCaps(context)),
                const SizedBox(height: 6),
                Text(
                  m.value,
                  style: HexaDsType.metricPrimary().copyWith(fontSize: 24),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value);
  final String label;
  final String value;
}
