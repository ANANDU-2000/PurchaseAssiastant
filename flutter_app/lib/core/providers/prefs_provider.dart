import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../notifications/local_notifications_service.dart';

/// SharedPreferences key for notification opt-in (also used at app startup).
const kNotificationsOptInKey = 'pref_notifications_opt_in';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden in ProviderScope');
});

final smartAutofillEnabledProvider = NotifierProvider<SmartAutofillNotifier, bool>(SmartAutofillNotifier.new);

class SmartAutofillNotifier extends Notifier<bool> {
  static const _k = 'pref_smart_autofill';

  @override
  bool build() {
    final p = ref.watch(sharedPreferencesProvider);
    return p.getBool(_k) ?? false;
  }

  Future<void> setValue(bool v) async {
    await ref.read(sharedPreferencesProvider).setBool(_k, v);
    state = v;
  }
}

final localNotificationsOptInProvider = NotifierProvider<LocalNotificationsNotifier, bool>(LocalNotificationsNotifier.new);

class LocalNotificationsNotifier extends Notifier<bool> {
  @override
  bool build() {
    final p = ref.watch(sharedPreferencesProvider);
    return p.getBool(kNotificationsOptInKey) ?? false;
  }

  Future<void> setValue(bool v) async {
    await ref.read(sharedPreferencesProvider).setBool(kNotificationsOptInKey, v);
    state = v;
    await LocalNotificationsService.instance.setOptIn(v);
  }
}
