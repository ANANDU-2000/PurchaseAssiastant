import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set before opening [PurchaseWizardPage] so the wizard selects this supplier after load.
final pendingPurchaseSupplierIdProvider = StateProvider<String?>((ref) => null);
