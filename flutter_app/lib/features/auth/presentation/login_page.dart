import 'dart:async';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/widgets/app_text_field.dart';
import '../../../../core/design_system/widgets/hexa_dialog.dart';
import '../../../../core/auth/auth_error_messages.dart';
import '../../../../core/auth/biometric_login.dart';
import '../../../../core/auth/auth_failure_policy.dart';
import '../../../../core/auth/session_notifier.dart';
import '../../../../core/providers/prefs_provider.dart';
import '../../../../core/router/post_auth_route.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/theme/hexa_colors.dart';
import 'auth_brand_assets.dart';
import 'widgets/auth_network_error_banner.dart';
import 'widgets/auth_page_shell.dart';

/// Keyboard-safe, centered card login (no hero image) — iOS + web friendly.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with TickerProviderStateMixin {
  final _loginEmail = TextEditingController();
  final _loginPass = TextEditingController();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();

  bool _loading = false;
  bool _obscure = true;
  bool _showValidation = false;
  bool _showNetworkBanner = false;
  DioException? _lastNetworkError;
  String? _inlineAuthError;
  bool _handledDupEmailQuery = false;
  bool _handledOwnerOnlyNotice = false;
  bool _bioReady = false;
  String? _bioEmail;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  final _mobileScrollCtrl = ScrollController();
  final _headerKey = GlobalKey(debugLabel: 'loginHeader');

  @override
  void initState() {
    super.initState();
    _loginEmail.addListener(_clearInlineErrors);
    _loginPass.addListener(_clearInlineErrors);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _animController.forward();
        _tryResumeSession();
      }
      unawaited(_loadBiometricState());
    });
  }

  Future<void> _loadBiometricState() async {
    try {
      final email = await BiometricLogin.savedEmail();
      final can = await BiometricLogin.isAvailable();
      final t = await ref.read(tokenStoreProvider).read();
      final hasTokens = t.access != null && t.refresh != null;
      if (!mounted) return;
      setState(() {
        _bioEmail = email;
        _bioReady = can && email != null && email.isNotEmpty && hasTokens;
      });
    } catch (e) {
      developer.log('Failed to load biometric state: $e', name: 'login_page');
    }
  }

  void _clearInlineErrors() {
    if (_inlineAuthError != null) {
      setState(() => _inlineAuthError = null);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_handledDupEmailQuery) {
      try {
        final q = GoRouterState.of(context).uri.queryParameters['msg'];
        if (q == 'exists') {
          _handledDupEmailQuery = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _authSnack('This email is already registered. Please sign in below.');
            if (!mounted) return;
            context.go('/login');
          });
        }
      } catch (_) {}
    }
    if (!_handledOwnerOnlyNotice) {
      try {
        final notice =
            GoRouterState.of(context).uri.queryParameters['notice'];
        if (notice == 'session_expired') {
          _handledOwnerOnlyNotice = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _authSnack('Session expired. Please sign in again.');
          });
        } else if (notice == 'owner_only') {
          _handledOwnerOnlyNotice = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _authSnack(
              'Accounts are created by your owner. Sign in with the credentials they shared.',
            );
          });
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _mobileScrollCtrl.dispose();
    _animController.dispose();
    _loginEmail.removeListener(_clearInlineErrors);
    _loginPass.removeListener(_clearInlineErrors);
    _loginEmail.dispose();
    _loginPass.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  bool get _isFormValid {
    final email = _loginEmail.text.trim();
    final p = _loginPass.text;
    return email.contains('@') && email.length >= 5 && p.length >= 6;
  }

  String? _emailError() {
    if (!_showValidation) return null;
    final s = _loginEmail.text.trim();
    if (s.isEmpty || !s.contains('@')) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _passError() {
    if (!_showValidation) return null;
    if (_loginPass.text.isEmpty || _loginPass.text.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  void _goPostAuth() {
    final s = ref.read(sessionProvider);
    if (s == null) return;
    final prefs = ref.read(sharedPreferencesProvider);
    context.go(resolvePostAuthPath(s, prefs));
  }

  Future<void> _tryResumeSession() async {
    if (ref.read(authSessionExpiredProvider) ||
        ref.read(auth401CircuitOpenProvider)) {
      return;
    }
    final t = await ref.read(tokenStoreProvider).read();
    if (t.access == null || t.refresh == null) return;
    if (ref.read(sessionProvider) != null) {
      if (mounted) _goPostAuth();
      return;
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _showNetworkBanner = false;
      _lastNetworkError = null;
    });
    try {
      await ref.read(sessionProvider.notifier).restore().timeout(
            kIsWeb ? const Duration(seconds: 8) : const Duration(seconds: 25),
          );
    } on DioException catch (e) {
      if (mounted && isDioNoConnectionError(e)) {
        setState(() {
          _lastNetworkError = e;
          _showNetworkBanner = true;
        });
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loading = false);
    if (ref.read(sessionProvider) != null) {
      _goPostAuth();
    }
  }

  void _authSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _retryAfterNetwork() {
    if (_loading) return;
    setState(() {
      _showNetworkBanner = false;
      _lastNetworkError = null;
      _inlineAuthError = null;
    });
    if (_isFormValid) {
      _signIn();
    } else {
      setState(() => _showValidation = true);
    }
  }

  Future<void> _signIn() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _showValidation = true;
      _inlineAuthError = null;
    });
    if (!_isFormValid) return;

    setState(() {
      _loading = true;
      _showNetworkBanner = false;
      _lastNetworkError = null;
    });
    try {
      final email = _loginEmail.text.trim();
      await ref.read(sessionProvider.notifier).login(
            email: email,
            password: _loginPass.text,
          );
      await BiometricLogin.saveEmail(email);
      if (mounted) _goPostAuth();
    } on DioException catch (e) {
      if (!mounted) return;
      if (isDioNoConnectionError(e)) {
        setState(() {
          _lastNetworkError = e;
          _showNetworkBanner = true;
        });
        return;
      }
      final sc = e.response?.statusCode;
      if (sc == 401) {
        developer.log('Login failed: invalid credentials', name: 'login_page');
        setState(() {
          _inlineAuthError = 'Invalid email or password. Try again.';
        });
        return;
      }
      if (sc == 403) {
        final detail = e.response?.data;
        final msg = detail is Map ? detail['detail']?.toString() : null;
        developer.log('Login failed: account blocked/inactive (403)', name: 'login_page');
        setState(() {
          _inlineAuthError = msg?.toLowerCase().contains('blocked') == true
              ? 'This account is blocked. Contact your owner.'
              : (msg?.toLowerCase().contains('inactive') == true
                  ? 'This account is inactive.'
                  : 'Sign-in not allowed for this account.');
        });
        return;
      }
      if (sc == 422) {
        developer.log('Login failed: validation error (422)', name: 'login_page');
        setState(() {
          _inlineAuthError =
              'Use your full login email (e.g. 1234567890@staff.harisree.local) and password from the owner.';
        });
        return;
      }
      developer.log('Login failed: ${friendlyAuthError(e, context: AuthErrorContext.login)}', name: 'login_page');
      setState(() {
        _inlineAuthError = friendlyAuthError(e, context: AuthErrorContext.login);
      });
    } catch (e, st) {
      developer.log('Login failed with unexpected error: $e', name: 'login_page', error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          // Empty-workspace / invite messages from [SessionNotifier.login].
          if (e is StateError && e.message.trim().isNotEmpty) {
            _inlineAuthError = e.message;
          } else {
            _inlineAuthError = 'Something went wrong. Please try again.';
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithBiometric() async {
    if (_loading || !_bioReady) return;
    setState(() => _loading = true);
    try {
      final ok = await BiometricLogin.authenticate();
      if (!ok || !mounted) return;
      if (_bioEmail != null && _bioEmail!.isNotEmpty) {
        _loginEmail.text = _bioEmail!;
      }
      await ref.read(sessionProvider.notifier).restore();
      if (mounted && ref.read(sessionProvider) != null) {
        _goPostAuth();
      } else if (mounted) {
        setState(() {
          _inlineAuthError = 'Session expired — sign in with password once.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _inlineAuthError = 'Biometric sign-in failed. Use password.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build — responsive: mobile gets full-width frosted layout, desktop unchanged
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final eErr = _emailError();
    final pErr = _passError();

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: HexaResponsive.shouldResizeScaffoldForIme(context),
      body: MediaQuery(
        data: !context.isMobileLayout
            ? MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.zero)
            : MediaQuery.of(context),
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onTap: () => FocusScope.of(context).unfocus(),
          child: context.isMobileLayout
              ? _buildMobileLayout(eErr, pErr)
              : _buildDesktopLayout(eErr, pErr),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Desktop / Tablet layout — single scroll owner (AuthPageShell); no nested KSFV
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildDesktopLayout(String? eErr, String? pErr) {
    return AuthPageShell(
      children: [
        AuthFormCard(
          child: FocusTraversalGroup(
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warehouse_outlined,
                        size: 36,
                        color: HexaColors.brandPrimary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Harisree Agency',
                              style: HexaDsType.heading(24,
                                  color: HexaDsColors.textPrimary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Warehouse Management',
                              style: HexaDsType.body(14,
                                  color: HexaDsColors.textMuted,
                                  weight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Sign In',
                    textAlign: TextAlign.center,
                    style: HexaDsType.heading(20, color: HexaDsColors.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  if (_showNetworkBanner)
                    AuthNetworkErrorBanner(
                      onRetry: _retryAfterNetwork,
                      title: authUnreachableBannerTitle(_lastNetworkError),
                      detail: authServerUnreachableDetail(_lastNetworkError),
                    ),
                  AppTextField(
                    controller: _loginEmail,
                    focusNode: _emailFocus,
                    label: 'Email',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    errorText: eErr,
                    scrollPadding: HexaResponsive.authFieldScrollPadding(context),
                  ),
                  AppTextField(
                    controller: _loginPass,
                    focusNode: _passFocus,
                    label: 'Password',
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    errorText: pErr,
                    scrollPadding: HexaResponsive.authFieldScrollPadding(context),
                    onActionSubmit: _signIn,
                    suffix: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: HexaColors.gray500,
                        size: 22,
                      ),
                    ),
                  ),
                  if (_inlineAuthError != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _inlineAuthError!,
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  if (_bioReady) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton.tonalIcon(
                        onPressed: _loading ? null : _signInWithBiometric,
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              HexaColors.brandPrimary.withValues(alpha: 0.12),
                          foregroundColor: HexaColors.brandPrimary,
                        ),
                        icon: const Icon(Icons.fingerprint, size: 28),
                        label: const Text(
                          'Sign in with fingerprint / Face ID',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (_bioEmail != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _bioEmail!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: HexaColors.gray500,
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  AppLoadingButton(
                    label: 'Sign In',
                    loading: _loading,
                    onPressed: _signIn,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _loading
                          ? null
                          : () {
                              context.go('/forgot-password');
                            },
                      child: Text(
                        'Forgot password?',
                        style: HexaDsType.body(12,
                            color: HexaDsColors.textMuted,
                            weight: FontWeight.w500),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Contact your manager to reset password',
                      style: HexaDsType.body(12, color: HexaDsColors.textMuted),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (AppConfig.buildSha.isNotEmpty)
                    Text(
                      'Build ${AppConfig.buildSha}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  Text(
                    '© 2026',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Mobile layout — single scroll + glass card (no nested KSFV)
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildMobileLayout(String? eErr, String? pErr) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildMobileBackground(),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Align(
                alignment: keyboardOpen ? Alignment.topCenter : Alignment.center,
                child: SingleChildScrollView(
                  controller: _mobileScrollCtrl,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const ClampingScrollPhysics(),
                  // Scaffold owns IME inset — do not add viewInsets to padding.
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: keyboardOpen
                          ? 0
                          : (constraints.maxHeight - 48)
                              .clamp(0.0, double.infinity),
                    ),
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: _buildGlassContainer(
                          eErr,
                          pErr,
                          compact: keyboardOpen,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMobileBackground() {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: HexaColors.brandBackground),
        Image.asset(
          AuthBrandAssets.background,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => DecoratedBox(
            decoration: BoxDecoration(gradient: HexaColors.atmosphereGradient),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF062E28).withValues(alpha: 0.55),
                  HexaColors.brandPrimary.withValues(alpha: 0.65),
                  HexaColors.brandBackground.withValues(alpha: 0.88),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassContainer(
    String? eErr,
    String? pErr, {
    bool compact = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: kIsWeb ? 0.96 : 0.92),
        borderRadius: BorderRadius.circular(compact ? 20 : 28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!compact) ...[
              _buildLogoSection(),
              const SizedBox(height: 32),
              Text(
                'Sign In',
                textAlign: TextAlign.center,
                style: HexaDsType.heading(28,
                    color: HexaDsColors.textPrimary),
              ),
              const SizedBox(height: 32),
            ] else ...[
              // Short chrome so password focus need not scroll header off-screen.
              Text(
                key: _headerKey,
                'Harisree Agency',
                textAlign: TextAlign.center,
                style: HexaDsType.heading(18,
                    color: HexaDsColors.textPrimary),
              ),
              const SizedBox(height: 12),
            ],
            if (_showNetworkBanner)
              AuthNetworkErrorBanner(
                onRetry: _retryAfterNetwork,
                title: authUnreachableBannerTitle(_lastNetworkError),
                detail: authServerUnreachableDetail(_lastNetworkError),
              ),
            AppTextField(
              controller: _loginEmail,
              focusNode: _emailFocus,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              errorText: eErr,
            ),
            SizedBox(height: compact ? 12 : 16),
            AppTextField(
              controller: _loginPass,
              focusNode: _passFocus,
              label: 'Password',
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              errorText: pErr,
              onActionSubmit: _signIn,
              suffix: _buildPasswordToggle(),
            ),
            if (_inlineAuthError != null) ...[
              const SizedBox(height: 8),
              Text(
                _inlineAuthError!,
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (!compact && _bioReady) ...[
              const SizedBox(height: 16),
              _buildBiometricButton(),
              if (_bioEmail != null) ...[
                const SizedBox(height: 4),
                Text(
                  _bioEmail!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: HexaColors.gray500,
                  ),
                ),
              ],
            ],
            SizedBox(height: compact ? 16 : 24),
            _buildSignInButton(),
            if (!compact) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _loading
                      ? null
                      : () => context.go('/forgot-password'),
                  child: Text(
                    'Forgot password?',
                    style: HexaDsType.body(14,
                        color: HexaDsColors.textMuted,
                        weight: FontWeight.w500),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Contact your manager to reset password',
                  style:
                      HexaDsType.body(12, color: HexaDsColors.textMuted),
                ),
              ),
              const SizedBox(height: 8),
              if (AppConfig.buildSha.isNotEmpty)
                Text(
                  'Build ${AppConfig.buildSha}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                  ),
                ),
              Text(
                '© 2026',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLogoSection() {
    return Column(
      key: _headerKey,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              AuthBrandAssets.logo,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: HexaColors.brandPrimary,
                alignment: Alignment.center,
                child: const Text(
                  'H',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Harisree Agency',
          textAlign: TextAlign.center,
          style: HexaDsType.heading(26, color: HexaDsColors.textPrimary),
        ),
        const SizedBox(height: 8),
        Text(
          'Warehouse Management',
          textAlign: TextAlign.center,
          style: HexaDsType.body(15,
              color: HexaDsColors.textMuted, weight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildPasswordToggle() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: child,
      ),
      child: IconButton(
        key: ValueKey(_obscure),
        tooltip: _obscure ? 'Show password' : 'Hide password',
        onPressed: () => setState(() => _obscure = !_obscure),
        icon: Icon(
          _obscure
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          color: HexaColors.gray500,
          size: 22,
        ),
      ),
    );
  }

  Widget _buildBiometricButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.tonalIcon(
        onPressed: _loading ? null : _signInWithBiometric,
        style: FilledButton.styleFrom(
          backgroundColor: HexaColors.brandPrimary.withValues(alpha: 0.12),
          foregroundColor: HexaColors.brandPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: const Icon(Icons.fingerprint, size: 28),
        label: const Text(
          'Sign in with fingerprint / Face ID',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildSignInButton() {
    return AppLoadingButton(
      label: 'Sign In',
      loading: _loading,
      onPressed: _signIn,
    );
  }
}
