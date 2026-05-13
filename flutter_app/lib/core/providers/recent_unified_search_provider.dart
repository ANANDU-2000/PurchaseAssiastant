import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import 'prefs_provider.dart';

/// Recent unified-search strings (per signed-in business), persisted in SharedPreferences.
final recentUnifiedSearchQueriesProvider =
    NotifierProvider<RecentUnifiedSearchQueriesNotifier, List<String>>(
        RecentUnifiedSearchQueriesNotifier.new);

class RecentUnifiedSearchQueriesNotifier extends Notifier<List<String>> {
  static const _kPrefix = 'pref_recent_unified_search_v1_';

  @override
  List<String> build() {
    final session = ref.watch(sessionProvider);
    final p = ref.watch(sharedPreferencesProvider);
    if (session == null) return [];
    final k = _key(session.primaryBusiness.id);
    return List<String>.from(p.getStringList(k) ?? []);
  }

  String _key(String businessId) => '$_kPrefix$businessId';

  Future<void> addQuery(String raw) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final t = raw.trim();
    if (t.length < 2 || t.length > 200) return;
    final p = ref.read(sharedPreferencesProvider);
    final k = _key(session.primaryBusiness.id);
    final cur = List<String>.from(p.getStringList(k) ?? []);
    cur.removeWhere((e) => e.toLowerCase() == t.toLowerCase());
    cur.insert(0, t);
    while (cur.length > 12) {
      cur.removeLast();
    }
    await p.setStringList(k, cur);
    state = cur;
  }

  Future<void> removeAt(int index) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    if (index < 0 || index >= state.length) return;
    final p = ref.read(sharedPreferencesProvider);
    final k = _key(session.primaryBusiness.id);
    final cur = List<String>.from(state)..removeAt(index);
    await p.setStringList(k, cur);
    state = cur;
  }
}
