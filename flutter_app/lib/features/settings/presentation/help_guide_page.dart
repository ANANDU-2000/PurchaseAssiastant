import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/navigation_ext.dart';

class HelpGuidePage extends StatelessWidget {
  const HelpGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & guide'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/settings'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            'Harisree warehouse operating guide',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          _GuideCard(
            title: 'Daily stock truth',
            items: const [
              'Formal purchase orders add stock only after delivery is confirmed.',
              'Staff cash buys: open Stock, tap an item, then Quick purchase.',
              'Physical count records do not change stock unless you choose Update stock.',
            ],
          ),
          _GuideCard(
            title: 'Offline mode',
            items: const [
              'If the offline banner is visible, check existing data but avoid final money decisions.',
              'PDF and backup exports need network because files are generated or shared from fresh data.',
              'When network returns, refresh Home or Stock before confirming counts.',
            ],
          ),
          _GuideCard(
            title: 'Opening stock and backup',
            items: const [
              'Owners should complete Opening stock setup before daily operations.',
              'Settings → Export & Backup: stock Excel, monthly purchases PDF, ZIP CSV.',
              'Keep one recent backup outside the phone before large cleanups or audits.',
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => context.push('/settings/backup'),
            icon: const Icon(Icons.backup_outlined),
            label: const Text('Open Export & Backup'),
          ),
        ],
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('- '),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
