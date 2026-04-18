import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import '../models/business_profile.dart';

/// Non-null profile for PDFs (from session primary business).
final invoiceBusinessProfileProvider = Provider<BusinessProfile>((ref) {
  final session = ref.watch(sessionProvider);
  if (session == null) {
    return const BusinessProfile(
      legalName: 'Workspace',
      displayTitle: 'Purchase invoice',
    );
  }
  return BusinessProfile.fromBusinessBrief(session.primaryBusiness);
});
