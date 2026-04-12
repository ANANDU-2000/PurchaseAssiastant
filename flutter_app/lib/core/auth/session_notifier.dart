import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/hexa_api.dart';
import '../models/session.dart';
import '../providers/prefs_provider.dart';
import 'google_sign_in_helper.dart';
import 'secure_token_store.dart';
import 'session_cache.dart';

/// Bumps when session changes — wired to [GoRouter.refreshListenable].
final authRefresh = ValueNotifier<int>(0);

final hexaApiProvider = Provider<HexaApi>((ref) {
  late final HexaApi api;
  api = HexaApi(
    onUnauthorizedRefresh: () async {
      final store = ref.read(tokenStoreProvider);
      final t = await store.read();
      if (t.refresh == null) return false;
      try {
        final pair = await api.refreshTokens(refreshToken: t.refresh!);
        await store.write(access: pair.access, refresh: pair.refresh);
        api.setAuthToken(pair.access);
        await ref.read(sessionProvider.notifier).applyRefreshedTokens(pair.access, pair.refresh);
        return true;
      } catch (_) {
        // Refresh token invalid (wrong server DB, rotated JWT secret, revoked). Clear storage
        // or the app keeps sending dead tokens and spams 401 in the console.
        await ref.read(sessionProvider.notifier).logout();
        return false;
      }
    },
  );
  return api;
});

final tokenStoreProvider = Provider<SecureTokenStore>((ref) {
  return SecureTokenStore(ref.watch(sharedPreferencesProvider));
});

final sessionProvider = NotifierProvider<SessionNotifier, Session?>(SessionNotifier.new);

class SessionNotifier extends Notifier<Session?> {
  @override
  Session? build() => null;

  Future<void> applyRefreshedTokens(String access, String refresh) async {
    final cur = state;
    if (cur == null) return;
    state = Session(accessToken: access, refreshToken: refresh, businesses: cur.businesses);
  }

  Future<void> _persistSession(Session session) async {
    final cache = SessionCache(ref.read(sharedPreferencesProvider));
    await cache.saveBusinesses(session.businesses);
  }

  Future<void> restore() async {
    final store = ref.read(tokenStoreProvider);
    final api = ref.read(hexaApiProvider);
    final cache = SessionCache(ref.read(sharedPreferencesProvider));
    ({String? access, String? refresh}) t;
    try {
      t = await store.read();
    } catch (_) {
      state = null;
      authRefresh.value++;
      return;
    }
    if (t.access == null || t.refresh == null) {
      state = null;
      authRefresh.value++;
      return;
    }
    api.setAuthToken(t.access);

    Future<void> finishOk(List<BusinessBrief> businesses) async {
      if (businesses.isEmpty) {
        state = null;
        await store.clear();
        await cache.clear();
        api.setAuthToken(null);
        authRefresh.value++;
        return;
      }
      final session = Session(accessToken: t.access!, refreshToken: t.refresh!, businesses: businesses);
      state = session;
      await _persistSession(session);
      authRefresh.value++;
    }

    try {
      final businesses = await api.meBusinesses();
      await finishOk(businesses);
    } on DioException catch (e) {
      final sc = e.response?.statusCode;
      if (sc == 401) {
        // Interceptor may have already cleared tokens via logout() after a failed refresh.
        final still = await store.read();
        if (still.access == null || still.refresh == null) {
          api.setAuthToken(null);
          state = null;
          authRefresh.value++;
          return;
        }
        try {
          final pair = await api.refreshTokens(refreshToken: still.refresh!);
          await store.write(access: pair.access, refresh: pair.refresh);
          api.setAuthToken(pair.access);
          final businesses = await api.meBusinesses();
          if (businesses.isEmpty) {
            await store.clear();
            await cache.clear();
            api.setAuthToken(null);
            state = null;
            authRefresh.value++;
            return;
          }
          final session = Session(accessToken: pair.access, refreshToken: pair.refresh, businesses: businesses);
          state = session;
          await _persistSession(session);
          authRefresh.value++;
          return;
        } catch (_) {
          await store.clear();
          await cache.clear();
          api.setAuthToken(null);
          state = null;
          authRefresh.value++;
          return;
        }
      }
      if (_isRecoverableNetworkError(e)) {
        final cached = cache.loadBusinesses();
        if (cached != null && cached.isNotEmpty) {
          state = Session(accessToken: t.access!, refreshToken: t.refresh!, businesses: cached);
          authRefresh.value++;
          return;
        }
        state = null;
        authRefresh.value++;
        return;
      }
      final cached = cache.loadBusinesses();
      if (cached != null && cached.isNotEmpty) {
        state = Session(accessToken: t.access!, refreshToken: t.refresh!, businesses: cached);
        authRefresh.value++;
        return;
      }
      state = null;
      authRefresh.value++;
    } catch (_) {
      final cached = cache.loadBusinesses();
      if (cached != null && cached.isNotEmpty) {
        state = Session(accessToken: t.access!, refreshToken: t.refresh!, businesses: cached);
        authRefresh.value++;
        return;
      }
      state = null;
      authRefresh.value++;
    }
  }

  bool _isRecoverableNetworkError(DioException e) {
    if (e.response != null) return false;
    final t = e.type;
    return t == DioExceptionType.connectionTimeout ||
        t == DioExceptionType.sendTimeout ||
        t == DioExceptionType.receiveTimeout ||
        t == DioExceptionType.connectionError ||
        (t == DioExceptionType.unknown && e.response == null);
  }

  Future<void> login({required String email, required String password}) async {
    final api = ref.read(hexaApiProvider);
    final store = ref.read(tokenStoreProvider);
    final tokens = await api.login(email: email, password: password);
    await store.write(access: tokens.access, refresh: tokens.refresh);
    api.setAuthToken(tokens.access);
    final businesses = await api.meBusinesses();
    final session = Session(accessToken: tokens.access, refreshToken: tokens.refresh, businesses: businesses);
    state = session;
    await _persistSession(session);
    authRefresh.value++;
  }

  Future<void> register({required String username, required String email, required String password}) async {
    final api = ref.read(hexaApiProvider);
    final store = ref.read(tokenStoreProvider);
    final tokens = await api.register(username: username, email: email, password: password);
    await store.write(access: tokens.access, refresh: tokens.refresh);
    api.setAuthToken(tokens.access);
    final businesses = await api.meBusinesses();
    final session = Session(accessToken: tokens.access, refreshToken: tokens.refresh, businesses: businesses);
    state = session;
    await _persistSession(session);
    authRefresh.value++;
  }

  Future<void> signInWithGoogle({required String idToken}) async {
    final api = ref.read(hexaApiProvider);
    final store = ref.read(tokenStoreProvider);
    final tokens = await api.loginWithGoogle(idToken: idToken);
    await store.write(access: tokens.access, refresh: tokens.refresh);
    api.setAuthToken(tokens.access);
    final businesses = await api.meBusinesses();
    final session = Session(accessToken: tokens.access, refreshToken: tokens.refresh, businesses: businesses);
    state = session;
    await _persistSession(session);
    authRefresh.value++;
  }

  Future<void> logout() async {
    final api = ref.read(hexaApiProvider);
    final store = ref.read(tokenStoreProvider);
    final cache = SessionCache(ref.read(sharedPreferencesProvider));
    await signOutGoogleIfNeeded();
    await store.clear();
    await cache.clear();
    api.setAuthToken(null);
    state = null;
    authRefresh.value++;
  }
}
