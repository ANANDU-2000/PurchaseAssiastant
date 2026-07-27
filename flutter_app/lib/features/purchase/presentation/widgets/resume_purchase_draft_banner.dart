import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/providers/business_write_revision.dart';
import '../../../../core/services/offline_store.dart';
import '../../../../core/theme/hexa_colors.dart';

/// Shown when a local purchase wizard draft exists (Hive + prefs restore).
class ResumePurchaseDraftBanner extends ConsumerWidget {
  const ResumePurchaseDraftBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(businessDataWriteRevisionProvider);
    final s = ref.watch(sessionProvider);
    if (s == null) return const SizedBox.shrink();
    final bid = s.primaryBusiness.id;
    final raw = OfflineStore.getPurchaseWizardDraft(bid);
    if (raw == null || raw.isEmpty) return const SizedBox.shrink();

    var subtitle = 'Continue where you left off';
    try {
      final o = jsonDecode(raw);
      if (o is Map) {
        final meta = o['draftWizardMeta'];
        if (meta is Map && meta['savedAt'] != null) {
          final dt = DateTime.tryParse(meta['savedAt'].toString());
          if (dt != null) {
            subtitle = 'Saved ${DateFormat('MMM d · h:mm a').format(dt)}';
          }
        }
      }
    } catch (_) {}

    return Material(
      color: const Color(0xFFE8F9F7),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.pushNamed(
          'purchase_new',
          extra: <String, dynamic>{'resumeDraft': true},
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: HexaColors.brandPrimary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resume purchase draft',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF555555),
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF333333)),
            ],
          ),
        ),
      ),
    );
  }
}
