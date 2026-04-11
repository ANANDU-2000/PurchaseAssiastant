import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/hexa_api.dart';
import '../models/session.dart';
import 'google_sign_in_helper.dart';
import 'secure_token_store.dart';

/// Bumps when session changes — wired to [GoRouter.refreshListenable].
final authRefresh = ValueNotifier<int>(0);

final hexaApiProvider = Provider<HexaApi>((ref) => HexaApi());

final tokenStoreProvider = Provider<SecureTokenStore>((ref) => SecureTokenStore());

final sessionProvider = NotifierProvider<SessionNotifier, Session?>(SessionNotifier.new);

class SessionNotifier extends Notifier<Session?> {
  @override
  Session? build() => null;

  Future<void> restore() async {
    final store = ref.read(tokenStoreProvider);
    final api = ref.read(hexaApiProvider);
    final t = await store.read();
    if (t.access == null || t.refresh == null) {
      state = null;
      authRefresh.value++;
      return;
    }
    api.setAuthToken(t.access);
    try {
      final businesses = await api.meBusinesses();
      if (businesses.isEmpty) {
        state = null;
        await store.clear();
        authRefresh.value++;
        return;
      }
      state = Session(accessToken: t.access!, refreshToken: t.refresh!, businesses: businesses);
      authRefresh.value++;
    } catch (_) {
      await store.clear();
      api.setAuthToken(null);
      state = null;
      authRefresh.value++;
    }
  }

  Future<void> login({required String emailOrUsername, required String password}) async {
    final api = ref.read(hexaApiProvider);
    final store = ref.read(tokenStoreProvider);
    final tokens = await api.login(emailOrUsername: emailOrUsername, password: password);
    await store.write(access: tokens.access, refresh: tokens.refresh);
    api.setAuthToken(tokens.access);
    final businesses = await api.meBusinesses();
    state = Session(accessToken: tokens.access, refreshToken: tokens.refresh, businesses: businesses);
    authRefresh.value++;
  }

  Future<void> register({required String username, required String email, required String password}) async {
    final api = ref.read(hexaApiProvider);
    final store = ref.read(tokenStoreProvider);
    final tokens = await api.register(username: username, email: email, password: password);
    await store.write(access: tokens.access, refresh: tokens.refresh);
    api.setAuthToken(tokens.access);
    final businesses = await api.meBusinesses();
    state = Session(accessToken: tokens.access, refreshToken: tokens.refresh, businesses: businesses);
    authRefresh.value++;
  }

  Future<void> signInWithGoogle({required String idToken}) async {
    final api = ref.read(hexaApiProvider);
    final store = ref.read(tokenStoreProvider);
    final tokens = await api.loginWithGoogle(idToken: idToken);
    await store.write(access: tokens.access, refresh: tokens.refresh);
    api.setAuthToken(tokens.access);
    final businesses = await api.meBusinesses();
    state = Session(accessToken: tokens.access, refreshToken: tokens.refresh, businesses: businesses);
    authRefresh.value++;
  }

  Future<void> logout() async {
    final api = ref.read(hexaApiProvider);
    final store = ref.read(tokenStoreProvider);
    await signOutGoogleIfNeeded();
    await store.clear();
    api.setAuthToken(null);
    state = null;
    authRefresh.value++;
  }
}
