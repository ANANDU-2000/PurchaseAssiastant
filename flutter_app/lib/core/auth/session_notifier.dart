import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/hexa_api.dart';
import '../models/session.dart';
import '../providers/business_aggregates_invalidation.dart'
    show invalidateWorkspaceSeedData;
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
        await ref
            .read(sessionProvider.notifier)
            .applyRefreshedTokens(pair.access, pair.refresh);
        return true;
      } on DioException catch (e) {
        final sc = e.response?.statusCode;
        final invalidRefresh = sc == 401 || sc == 403;
        if (invalidRefresh) {
          await ref.read(sessionProvider.notifier).logout();
        }
        return false;
      } catch (_) {
        return false;
      }
    },
  );
  return api;
});

final tokenStoreProvider = Provider<SecureTokenStore>((ref) {
  return SecureTokenStore(ref.watch(sharedPreferencesProvider));
});

final sessionProvider =
    NotifierProvider<SessionNotifier, Session?>(SessionNotifier.new);

class SessionNotifier extends Notifier<Session?> {
  @override
  Session? build() => null;

  /// Serializes [restore], [login], [register], and [signInWithGoogle] so a concurrent
  /// [restore] (splash / login / cold start) cannot fire `logout()` from a dead refresh
  /// while new tokens are being written — which used to clear storage mid sign-up and
  /// leave the Create Account button spinning forever.
  Future<void> _authSerial = Future<void>.value();

  Future<T> _withAuthSerial<T>(Future<T> Function() fn) {
    final c = Completer<T>();
    _authSerial = _authSerial.then((_) async {
      try {
        if (!c.isCompleted) c.complete(await fn());
      } catch (e, st) {
        if (!c.isCompleted) c.completeError(e, st);
      }
    });
    return c.future;
  }

  Future<void> applyRefreshedTokens(String access, String refresh) async {
    final cur = state;
    if (cur == null) return;
    state = Session(
        accessToken: access, refreshToken: refresh, businesses: cur.businesses);
  }

  Future<void> _persistSession(Session session) async {
    final cache = SessionCache(ref.read(sharedPreferencesProvider));
    await cache.saveBusinesses(session.businesses);
  }

  /// Post-login bootstrap: does not block [restore] / [login] UI — runs after a microtask.
  /// Soft-fail: [HexaApi.bootstrapWorkspace] returns null on 404/501 (older server).
  void _scheduleWorkspaceBootstrap() {
    unawaited(_deferredWorkspaceBootstrap());
  }

  Future<void> _deferredWorkspaceBootstrap() async {
    await Future<void>.delayed(Duration.zero);
    final session = state;
    if (session == null) return;
    final accessToken = session.accessToken;
    final api = ref.read(hexaApiProvider);
    try {
      final boot = await api.bootstrapWorkspace();
      if (boot == null) return;
      if (boot['created_business'] == true) {
        final list = await api.meBusinesses();
        if (state == null) return;
        if (state!.accessToken != accessToken) return;
        state = Session(
          accessToken: state!.accessToken,
          refreshToken: state!.refreshToken,
          businesses: list,
        );
        await _persistSession(state!);
        authRefresh.value++;
      }
      if (boot['seeded'] == true) {
        invalidateWorkspaceSeedData(ref);
      }
    } on DioException catch (e) {
      assert(() {
        debugPrint('deferred workspace bootstrap: ${e.message}');
        return true;
      }());
    } catch (e) {
      assert(() {
        debugPrint('deferred workspace bootstrap: $e');
        return true;
      }());
    }
  }

  Future<void> restore() => _withAuthSerial(_restoreImpl);

  Future<void> _restoreImpl() async {
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
      final session = Session(
          accessToken: t.access!,
          refreshToken: t.refresh!,
          businesses: businesses);
      state = session;
      await _persistSession(session);
      authRefresh.value++;
      _scheduleWorkspaceBootstrap();
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
          final session = Session(
              accessToken: pair.access,
              refreshToken: pair.refresh,
              businesses: businesses);
          state = session;
          await _persistSession(session);
          authRefresh.value++;
          return;
        } on DioException catch (re) {
          final rsc = re.response?.statusCode;
          // Once /me/businesses has already returned 401, any refresh failure
          // means this session cannot be trusted. Clear to prevent 401 loops.
          if (rsc == null || rsc == 401 || rsc == 403) {
            await store.clear();
            await cache.clear();
          }
          api.setAuthToken(null);
          state = null;
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
          state = Session(
              accessToken: t.access!,
              refreshToken: t.refresh!,
              businesses: cached);
          authRefresh.value++;
          return;
        }
        state = null;
        authRefresh.value++;
        return;
      }
      final cached = cache.loadBusinesses();
      if (cached != null && cached.isNotEmpty) {
        state = Session(
            accessToken: t.access!,
            refreshToken: t.refresh!,
            businesses: cached);
        authRefresh.value++;
        return;
      }
      state = null;
      authRefresh.value++;
    } catch (_) {
      final cached = cache.loadBusinesses();
      if (cached != null && cached.isNotEmpty) {
        state = Session(
            accessToken: t.access!,
            refreshToken: t.refresh!,
            businesses: cached);
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

  Future<void> login({required String email, required String password}) =>
      _withAuthSerial(() => _loginImpl(email: email, password: password));

  Future<void> _loginImpl(
      {required String email, required String password}) async {
    final api = ref.read(hexaApiProvider);
    final store = ref.read(tokenStoreProvider);
    api.setAuthToken(null);
    final tokens = await api.login(email: email, password: password);
    await store.write(access: tokens.access, refresh: tokens.refresh);
    api.setAuthToken(tokens.access);
    var businesses = await api.meBusinesses();
    var session = Session(
        accessToken: tokens.access,
        refreshToken: tokens.refresh,
        businesses: businesses);
    state = session;
    await _persistSession(session);
    authRefresh.value++;
    _scheduleWorkspaceBootstrap();
  }

  Future<void> register(
      {required String username,
      required String email,
      required String password,
      String? name}) =>
      _withAuthSerial(
        () => _registerImpl(
          username: username,
          email: email,
          password: password,
          name: name,
        ),
      );

  Future<void> _registerImpl({
    required String username,
    required String email,
    required String password,
    String? name,
  }) async {
    final api = ref.read(hexaApiProvider);
    final store = ref.read(tokenStoreProvider);
    api.setAuthToken(null);
    final tokens = await api.register(
        username: username,
        email: email,
        password: password,
        name: name);
    await store.write(access: tokens.access, refresh: tokens.refresh);
    api.setAuthToken(tokens.access);
    var businesses = await api.meBusinesses();
    var session = Session(
        accessToken: tokens.access,
        refreshToken: tokens.refresh,
        businesses: businesses);
    state = session;
    await _persistSession(session);
    authRefresh.value++;
    _scheduleWorkspaceBootstrap();
  }

  Future<void> signInWithGoogle({required String idToken}) =>
      _withAuthSerial(() => _signInWithGoogleImpl(idToken: idToken));

  Future<void> _signInWithGoogleImpl({required String idToken}) async {
    final api = ref.read(hexaApiProvider);
    final store = ref.read(tokenStoreProvider);
    api.setAuthToken(null);
    final tokens = await api.loginWithGoogle(idToken: idToken);
    await store.write(access: tokens.access, refresh: tokens.refresh);
    api.setAuthToken(tokens.access);
    var businesses = await api.meBusinesses();
    var session = Session(
        accessToken: tokens.access,
        refreshToken: tokens.refresh,
        businesses: businesses);
    state = session;
    await _persistSession(session);
    authRefresh.value++;
    _scheduleWorkspaceBootstrap();
  }

  /// Reload workspaces from API (e.g. after branding update).
  Future<void> refreshBusinesses() async {
    final cur = state;
    if (cur == null) return;
    final api = ref.read(hexaApiProvider);
    final businesses = await api.meBusinesses();
    state = Session(
      accessToken: cur.accessToken,
      refreshToken: cur.refreshToken,
      businesses: businesses,
    );
    await _persistSession(state!);
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
