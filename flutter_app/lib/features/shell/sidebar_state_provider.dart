import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/prefs_helper.dart';

const _kSidebarCollapsedKey = 'shell_sidebar_collapsed';

/// Whether the desktop sidebar is collapsed (icon-only) or expanded (icon + label).
///
/// Default is false (expanded). Persisted across sessions.
final sidebarCollapsedProvider =
    StateNotifierProvider<SidebarCollapsedNotifier, bool>((ref) {
  return SidebarCollapsedNotifier();
});

class SidebarCollapsedNotifier extends StateNotifier<bool> {
  SidebarCollapsedNotifier() : super(false) {
    _load();
  }

  void _load() {
    try {
      state = PrefsHelper.prefs.getBool(_kSidebarCollapsedKey) ?? false;
    } catch (_) {
      // Prefs not initialized yet — keep default.
    }
  }

  Future<void> toggle() async {
    state = !state;
    try {
      await PrefsHelper.prefs.setBool(_kSidebarCollapsedKey, state);
    } catch (_) {
      // Prefs not initialized — ignore persistence.
    }
  }
}
