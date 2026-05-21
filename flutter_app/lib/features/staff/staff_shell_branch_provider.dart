import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Staff bottom-nav indices — must match [StatefulShellRoute] branch order in
/// [app_router.dart] and [StaffShellScreen].
abstract final class StaffShellBranch {
  static const int home = 0;
  static const int stock = 1;
  static const int scan = 2;
  static const int history = 3;
  static const int search = 4;
}

final staffShellCurrentBranchProvider = StateProvider<int>(
  (ref) => StaffShellBranch.home,
);
