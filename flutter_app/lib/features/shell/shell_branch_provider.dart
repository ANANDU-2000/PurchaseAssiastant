import 'package:flutter_riverpod/flutter_riverpod.dart';

/// IndexedStack branch indices — must match [StatefulShellRoute] order in
/// [app_router.dart] and the bottom bar in [ShellScreen].
abstract final class ShellBranch {
  static const int home = 0;
  static const int reports = 1;
  static const int history = 2;
  static const int assistant = 3;
}

/// Last-selected main shell tab. Providers defer heavy network work until the
/// matching branch is visible (see [reportsPurchasesPayloadProvider],
/// [tradePurchasesListProvider]).
final shellCurrentBranchProvider = StateProvider<int>(
  (ref) => ShellBranch.home,
);
