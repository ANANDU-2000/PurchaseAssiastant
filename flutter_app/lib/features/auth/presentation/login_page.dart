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
import 'auth_hero_artwork.dart';

/// Premium iOS-style login: hero + bottom card, teal brand, validation + login dialog on failure.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _heroAsset = 'assets/login/login.png';

  final _loginEmail = TextEditingController();
  final _loginPass = TextEditingController();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();

  late final AnimationController _cardAnim;
  late final Animation<Offset> _cardSlide;

  bool _loading = false;
  bool _obscure = true;
  bool _showValidation = false;
  bool _buttonPressed = false;
  int _segmentIndex = 0;
  bool _heroPrecached = false;
  bool _didRedirectSignup = false;
  bool _handledDupEmailQuery = false;
  Size? _lastViewPhysicalSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cardAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _cardSlide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _cardAnim, curve: Curves.easeOutCubic));
    _loginEmail.addListener(() => setState(() {}));
    _loginPass.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cardAnim.forward();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryResumeSession());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_heroPrecached) {
      _heroPrecached = true;
      precacheImage(const AssetImage(_heroAsset), context);
    }
    if (!_handledDupEmailQuery) {
      try {
        final q = GoRouterState.of(context).uri.queryParameters['msg'];
        if (q == 'exists') {
          _handledDupEmailQuery = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _authSnack(
                'This email is already registered. Please sign in below.');
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
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!kIsWeb) return;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final v = views.first;
    if (v.viewInsets.bottom > 0) return;
    final sz = v.physicalSize;
    final prev = _lastViewPhysicalSize;
    _lastViewPhysicalSize = sz;
    if (prev == null || prev == sz) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cardAnim.dispose();
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
    setState(() => _loading = true);
    try {
      await ref.read(sessionProvider.notifier).restore().timeout(
            kIsWeb ? const Duration(seconds: 8) : const Duration(seconds: 25),
          );
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

  Future<void> _showLoginFailedDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Login Failed'),
        content: const Text('Incorrect email or password'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();
    setState(() => _showValidation = true);
    if (!_isFormValid) return;

    setState(() => _loading = true);
    try {
      await ref.read(sessionProvider.notifier).login(
            email: _loginEmail.text.trim(),
            password: _loginPass.text,
          );
      if (mounted) context.go('/home');
    } on DioException catch (e) {
      if (!mounted) return;
      final sc = e.response?.statusCode;
      if (sc == 401) {
        await _showLoginFailedDialog();
      } else {
        final msg = friendlyAuthError(e, context: AuthErrorContext.login);
        _authSnack(msg);
      }
    } catch (_) {
      if (mounted) {
        _authSnack('Something went wrong. Please try again.');
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
    setState(() => _loading = true);
    try {
      final account = await g.signIn();
      if (account == null) return;
      final auth = await account.authentication;
      final id = auth.idToken;
      if (id == null) throw StateError('No Google ID token');
      await ref.read(sessionProvider.notifier).signInWithGoogle(idToken: id);
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        _authSnack(friendlyGoogleSignInError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _forgotPassword() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forgot password?'),
        content: const Text(
          'Please contact your administrator to reset your password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Single-layer field: OutlineInputBorder only — no Container border on top.
  Widget _fieldShell({required bool err, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: child,
    );
  }

  OutlineInputBorder _ob(Color color, {double width = 1}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );

  InputDecoration _fieldDeco(
    String hint,
    IconData icon, {
    bool err = false,
    Widget? suffix,
  }) {
    final normal = _ob(Colors.grey.shade300);
    final error = _ob(Colors.red.shade600, width: 1.5);
    final focus = _ob(const Color(0xFF0E4F46), width: 1.5);
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),
      hintText: hint,
      hintStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: Color(0xFFAEAEB2),
      ),
      prefixIcon: Icon(icon, size: 20, color: const Color(0xFF8E8E93)),
      prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      suffixIcon: suffix,
      border: err ? error : normal,
      enabledBorder: err ? error : normal,
      focusedBorder: err ? error : focus,
      errorBorder: error,
      focusedErrorBorder: error,
    );
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

  Widget _brandHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: HexaColors.brandPrimary,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: const Text(
            'H',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppConfig.appName,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                  height: 1.15,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Purchase Intelligence',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF757575),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
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

  /// Shared field block (used in hero layout and in keyboard-top scroll layout).
  List<Widget> _loginFieldChildren(BuildContext context, {required bool showGoogle}) {
    final eErr = _emailError();
    final pErr = _passError();
    return [
      _fieldShell(
        err: eErr != null,
        child: TextField(
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
          decoration: _fieldDeco(
            'Email',
            Icons.mail_outline_rounded,
            err: eErr != null,
          ),
        ),
      ),
      _err(eErr),
      _fieldShell(
        err: pErr != null,
        child: TextField(
          controller: _loginPass,
          focusNode: _passFocus,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          onSubmitted: (_) => _signIn(),
          decoration: _fieldDeco(
            'Password',
            Icons.key_rounded,
            err: pErr != null,
            suffix: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: const Color(0xFF8E8E93),
                size: 22,
              ),
            ),
          ),
        ),
      ),
      _err(pErr),
      const SizedBox(height: 8),
      Listener(
        onPointerDown: (_) {
          if (_isFormValid && !_loading) {
            setState(() => _buttonPressed = true);
          }
        },
        onPointerUp: (_) => setState(() => _buttonPressed = false),
        onPointerCancel: (_) => setState(() => _buttonPressed = false),
        child: AnimatedScale(
          scale: (_buttonPressed && _isFormValid && !_loading) ? 0.98 : 1,
          duration: const Duration(milliseconds: 100),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: _loading ? null : (_isFormValid ? _signIn : null),
              style: FilledButton.styleFrom(
                backgroundColor: HexaColors.brandPrimary,
                disabledBackgroundColor: const Color(0xFFE5E7EB),
                disabledForegroundColor: const Color(0xFF6B7280),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
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
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _loading ? null : _forgotPassword,
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
          onPressed: _loading ? null : () => context.go('/signup'),
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
                borderRadius: BorderRadius.circular(14),
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
        '${AppConfig.appName} © 2026',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey.shade600,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final heroH = h * 0.45;
    final cardH = h * 0.60;
    final showGoogle = AppConfig.googleOAuthClientId.isNotEmpty;
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    if (inset > 8) {
      return Scaffold(
        backgroundColor: HexaColors.brandBackground,
        resizeToAvoidBottomInset: true,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + inset),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _brandHeader(),
                    const SizedBox(height: 16),
                    _segmented(),
                    const SizedBox(height: 18),
                    ..._loginFieldChildren(context, showGoogle: showGoogle),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AuthHeroArtwork(assetPath: _heroAsset, height: heroH),
              Align(
                alignment: Alignment.bottomCenter,
                child: SlideTransition(
                  position: _cardSlide,
                  child: Container(
                    height: cardH,
                    decoration: const BoxDecoration(
                      color: HexaColors.brandBackground,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 24,
                          offset: Offset(0, -4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                              child: AutofillGroup(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _brandHeader(),
                                    const SizedBox(height: 16),
                                    _segmented(),
                                    const SizedBox(height: 18),
                                    Expanded(
                                      child: ListView(
                                        physics: const ClampingScrollPhysics(),
                                        padding: EdgeInsets.zero,
                                        children: _loginFieldChildren(
                                          context,
                                          showGoogle: showGoogle,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? HexaColors.brandPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
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
