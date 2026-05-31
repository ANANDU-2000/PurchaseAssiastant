import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/shell/shell_branch_provider.dart';

/// Default shell location for each IndexedStack branch.
String shellLocationForBranch(int branch) => switch (branch) {
      ShellBranch.home => '/home',
      ShellBranch.stock => '/stock',
      ShellBranch.reports => '/reports',
      ShellBranch.history => '/purchase',
      ShellBranch.search => '/search',
      _ => '/home',
    };

void _applyShellTabSwitch(
  ProviderContainer container,
  BuildContext context, {
  required int branch,
  required String path,
}) {
  container.read(shellReturnBranchProvider.notifier).state =
      container.read(shellCurrentBranchProvider);
  try {
    final shell = StatefulNavigationShell.of(context);
    container.read(shellCurrentBranchProvider.notifier).state = branch;
    shell.goBranch(branch);
  } catch (_) {
    container.read(shellCurrentBranchProvider.notifier).state = branch;
  }
  context.go(path);
}

/// Records the current branch, then switches shell tab (use for Home cards → Reports/Stock).
void goShellTab(
  BuildContext context,
  WidgetRef ref, {
  required int branch,
  required String location,
}) {
  final path = location.startsWith('/') ? location : '/$location';
  _applyShellTabSwitch(
    ProviderScope.containerOf(context),
    context,
    branch: branch,
    path: path,
  );
}

/// Same as [goShellTab] for [StatelessWidget] callers without [WidgetRef].
void goShellTabFromContext(
  BuildContext context, {
  required int branch,
  required String location,
}) {
  final path = location.startsWith('/') ? location : '/$location';
  _applyShellTabSwitch(
    ProviderScope.containerOf(context),
    context,
    branch: branch,
    path: path,
  );
}

/// Pop or return to the branch recorded by [goShellTab].
void popShellTabOrGoHome(
  BuildContext context,
  WidgetRef ref, {
  required String homePath,
}) {
  final ret = ref.read(shellReturnBranchProvider);
  if (ret != null) {
    ref.read(shellReturnBranchProvider.notifier).state = null;
    goShellTab(context, ref, branch: ret, location: shellLocationForBranch(ret));
    return;
  }
  context.go(homePath);
}
