import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/google_sign_in_helper.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/hexa_colors.dart';
import 'widgets/auth_input_styles.dart';
import 'widgets/auth_network_error_banner.dart';
import 'widgets/auth_page_shell.dart';

/// Keyboard-safe, centered card login (no hero image) — iOS + web friendly.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
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
  int _segmentIndex = 0;
  bool _didRedirectSignup = false;
  bool _handledDupEmailQuery = false;

  @override
  void initState() {
    super.initState();
    _loginEmail.addListener(_clearInlineErrors);
    _loginPass.addListener(_clearInlineErrors);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tryResumeSession();
    });
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
    if (_didRedirectSignup) return;
    String? tabParam;
    try {
      tabParam = GoRouterState.of(context).uri.queryParameters['tab'];
    } catch (_) {
      tabParam = null;
    }
    if (tabParam == 'signup') {
      _didRedirectSignup = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/signup');
      });
    }
  }

  @override
  void dispose() {
    _loginEmail.removeListener(_clearInlineErrors);
    _loginPass.removeListener(_clearInlineErrors);
    _loginEmail.dispose();
    _loginPass.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  bool _emailValid(String v) {
    final s = v.trim();
    return s.contains('@') && RegExp(r'^[\w.+-]+@[\w.-]+\.\w{2,}$').hasMatch(s);
  }

  bool get _isFormValid {
    final email = _loginEmail.text.trim();
    final p = _loginPass.text;
    return _emailValid(email) && p.length >= 6;
  }

  String? _emailError() {
    if (!_showValidation) return null;
    final s = _loginEmail.text.trim();
    if (s.isEmpty || !_emailValid(s)) return 'Enter a valid email';
    return null;
  }

  String? _passError() {
    if (!_showValidation) return null;
    if (_loginPass.text.isEmpty || _loginPass.text.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  Future<void> _tryResumeSession() async {
    final t = await ref.read(tokenStoreProvider).read();
    if (t.access == null || t.refresh == null) return;
    if (ref.read(sessionProvider) != null) {
      if (mounted) context.go('/home');
      return;
    }
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
      context.go('/home');
    }
  }

  void _authSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _retryAfterNetwork() {
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
      await ref.read(sessionProvider.notifier).login(
            email: _loginEmail.text.trim(),
            password: _loginPass.text,
          );
      if (mounted) context.go('/home');
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
        setState(() {
          _inlineAuthError = 'Wrong email or password. Try again.';
        });
        return;
      }
      setState(() {
        _inlineAuthError = friendlyAuthError(e, context: AuthErrorContext.login);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _inlineAuthError = 'Something went wrong. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignIn() async {
    final g = googleSignInIfConfigured();
    if (g == null) {
      if (!mounted) return;
      if (kDebugMode) {
        _authSnack('Google sign-in needs OAuth setup in this build.');
      } else {
        _authSnack('Google sign-in is not available in this version.');
      }
      return;
    }
    setState(() {
      _loading = true;
      _showNetworkBanner = false;
      _lastNetworkError = null;
      _inlineAuthError = null;
    });
    try {
      final account = await g.signIn();
      if (account == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final auth = await account.authentication;
      final id = auth.idToken;
      if (id == null) throw StateError('No Google ID token');
      await ref.read(sessionProvider.notifier).signInWithGoogle(idToken: id);
      if (mounted) context.go('/home');
    } on DioException catch (e) {
      if (mounted) {
        if (isDioNoConnectionError(e)) {
          setState(() {
            _lastNetworkError = e;
            _showNetworkBanner = true;
          });
        } else {
          _authSnack(friendlyGoogleSignInError(e));
        }
      }
    } catch (e) {
      if (mounted) {
        _authSnack(friendlyGoogleSignInError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _err(String? m) {
    if (m == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        m,
        style: TextStyle(
          color: Colors.red.shade700,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _segmented() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            Expanded(
              child: _SegmentChip(
                label: 'Sign In',
                selected: _segmentIndex == 0,
                onTap: () => setState(() => _segmentIndex = 0),
              ),
            ),
            const SizedBox(width: 3),
            Expanded(
              child: _SegmentChip(
                label: 'Create Account',
                selected: false,
                onTap: () {
                  if (!mounted) return;
                  FocusScope.of(context).unfocus();
                  context.go('/signup');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eErr = _emailError();
    final pErr = _passError();
    final showGoogle = AppConfig.googleOAuthClientId.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFE8F5F2),
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: () => FocusScope.of(context).unfocus(),
        child: AuthPageShell(
          children: [
            AuthFormCard(
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _segmented(),
                    const SizedBox(height: 12),
                    if (_showNetworkBanner)
                      AuthNetworkErrorBanner(
                        onRetry: _retryAfterNetwork,
                        title: authUnreachableBannerTitle(_lastNetworkError),
                        detail: authServerUnreachableDetail(_lastNetworkError),
                      ),
                    TextField(
                      controller: _loginEmail,
                      focusNode: _emailFocus,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      onSubmitted: (_) => _passFocus.requestFocus(),
                      decoration: authFilledDecoration(
                        'Email',
                        icon: Icons.mail_outline_rounded,
                        err: eErr != null,
                      ),
                    ),
                    _err(eErr),
                    TextField(
                      controller: _loginPass,
                      focusNode: _passFocus,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      onSubmitted: (_) {
                        if (_isFormValid) _signIn();
                      },
                      decoration: authFilledDecoration(
                        'Password',
                        icon: Icons.key_rounded,
                        err: pErr != null,
                        suffix: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: const Color(0xFF6B7280),
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                    _err(pErr),
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
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: _loading
                            ? null
                            : (_isFormValid
                                ? _signIn
                                : () => setState(() => _showValidation = true)),
                        style: FilledButton.styleFrom(
                          backgroundColor: HexaColors.brandPrimary,
                          disabledBackgroundColor: const Color(0xFFE5E7EB),
                          disabledForegroundColor: const Color(0xFF6B7280),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Sign In'),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                        child: TextButton(
                        onPressed: _loading
                            ? null
                            : () {
                                // go() avoids a stale stack on web refresh/back.
                                context.go('/forgot-password');
                              },
                        child: const Text(
                          'Forgot password?',
                          style: TextStyle(
                            color: HexaColors.brandAccent,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: TextButton(
                        onPressed: _loading
                            ? null
                            : () => context.go('/signup'),
                        child: const Text(
                          'Create account',
                          style: TextStyle(
                            color: HexaColors.brandAccent,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    if (showGoogle) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(child: Divider(color: Colors.grey.shade300)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'or',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.grey.shade300)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _loading ? null : _googleSignIn,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0F172A),
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Continue with Google',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
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
          ],
        ),
      ),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? HexaColors.brandPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }
}
