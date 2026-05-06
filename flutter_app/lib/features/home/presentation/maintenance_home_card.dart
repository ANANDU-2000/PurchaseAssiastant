import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hexa_purchase_assistant/core/maintenance/maintenance_payment_constants.dart';
import 'package:hexa_purchase_assistant/core/maintenance/maintenance_payment_repository.dart';
import 'package:hexa_purchase_assistant/core/maintenance/maintenance_ui_status.dart';
import 'package:hexa_purchase_assistant/core/providers/maintenance_payment_provider.dart';
import 'package:hexa_purchase_assistant/core/theme/hexa_colors.dart';
import 'package:hexa_purchase_assistant/core/widgets/friendly_load_error.dart';

String _lastDayText(DateTime now) {
  final y = now.year;
  final m = now.month;
  final d = MaintenancePaymentRepository.lastDayOfMonth(y, m);
  final last = DateTime(y, m, d);
  return DateFormat('MMM d, y').format(last);
}

class MaintenanceHomeCard extends ConsumerWidget {
  const MaintenanceHomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(maintenancePaymentControllerProvider);
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (_, __) => FriendlyLoadError(
        message: 'Unable to load maintenance data',
        onRetry: () => ref
            .read(maintenancePaymentControllerProvider.notifier)
            .load(),
      ),
      data: (v) {
        if (v?.userVisibleError != null) {
          return FriendlyLoadError(
            message: v!.userVisibleError!,
            onRetry: () => ref
                .read(maintenancePaymentControllerProvider.notifier)
                .load(),
          );
        }
        final cur = v?.current;
        final st = v?.status;
        if (cur == null || st == null) {
          return const SizedBox.shrink();
        }
        if (st == MaintenanceUiStatus.paid) {
          return const SizedBox.shrink();
        }
        final now = DateTime.now();
        final chipColor = switch (st) {
          MaintenanceUiStatus.paid => const Color(0xFF16A34A),
          MaintenanceUiStatus.upcoming => HexaColors.textSecondary,
          MaintenanceUiStatus.dueToday => const Color(0xFFF59E0B),
          MaintenanceUiStatus.overdue => const Color(0xFFDC2626),
        };
        final chipLabel = switch (st) {
          MaintenanceUiStatus.paid => 'Paid',
          MaintenanceUiStatus.upcoming => 'Upcoming',
          MaintenanceUiStatus.dueToday => 'Due today',
          MaintenanceUiStatus.overdue => 'Overdue',
        };
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.build_circle_outlined,
                      size: 18,
                      color: chipColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Maintenance',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            'Due ${_lastDayText(now)} · 9:00',
                            style: const TextStyle(
                              fontSize: 10,
                              color: HexaColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₹${cur.amount}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: chipColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        chipLabel,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: chipColor,
                        ),
                      ),
                    ),
                  ],
                ),
                if (st != MaintenanceUiStatus.paid) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () async {
                          final uri = Uri.parse(
                            MaintenancePaymentConstants.upiUri,
                          );
                          if (!await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          )) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not open a UPI app. Try again or pay manually.',
                                ),
                              ),
                            );
                          }
                        },
                        child: const Text(
                          'Pay via UPI',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _showMarkPaidDialog(context, ref),
                        child: const Text(
                          'Mark as paid',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> _showMarkPaidDialog(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Mark maintenance as paid?'),
      content: const Text(
        'Only confirm if you have already sent ₹2,500 for this month. '
        'This records payment on this device only.',
      ),
      actions: [
        TextButton(
          onPressed: () => ctx.pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => ctx.pop(true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    await ref.read(maintenancePaymentControllerProvider.notifier).markPaid();
  }
}
