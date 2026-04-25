import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../notifications/local_notifications_service.dart';

/// SharedPreferences key for notification opt-in (also used at app startup).
const kNotificationsOptInKey = 'pref_notifications_opt_in';

/// After first successful session, we prompt once for iOS notification permission.
const kPostLoginNotifPermissionAskedKey = 'pref_post_login_notif_permission';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
      'sharedPreferencesProvider must be overridden in ProviderScope');
});

final smartAutofillEnabledProvider =
    NotifierProvider<SmartAutofillNotifier, bool>(SmartAutofillNotifier.new);

final quickSavePurchaseProvider =
    NotifierProvider<QuickSavePurchaseNotifier, bool>(
        QuickSavePurchaseNotifier.new);

class QuickSavePurchaseNotifier extends Notifier<bool> {
  static const _k = 'pref_quick_save_purchase';

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

final localNotificationsOptInProvider =
    NotifierProvider<LocalNotificationsNotifier, bool>(
        LocalNotificationsNotifier.new);

const kThemeModeKey = 'pref_theme_mode';

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final p = ref.watch(sharedPreferencesProvider);
    final v = p.getString(kThemeModeKey);
    if (v == 'dark') return ThemeMode.dark;
    // Default: light (iOS-like surfaces); users can switch to dark in Settings.
    return ThemeMode.light;
  }

  Future<void> setMode(ThemeMode mode) async {
    await ref.read(sharedPreferencesProvider).setString(
          kThemeModeKey,
          mode == ThemeMode.light ? 'light' : 'dark',
        );
    state = mode;
  }
}

class LocalNotificationsNotifier extends Notifier<bool> {
  @override
  bool build() {
    final p = ref.watch(sharedPreferencesProvider);
    return p.getBool(kNotificationsOptInKey) ?? false;
  }

  Future<void> setValue(bool v) async {
    await ref
        .read(sharedPreferencesProvider)
        .setBool(kNotificationsOptInKey, v);
    state = v;
    await LocalNotificationsService.instance.setOptIn(v);
  }
}
