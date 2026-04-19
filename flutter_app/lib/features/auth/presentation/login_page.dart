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
import '../../../core/theme/hexa_outline_input_border.dart';
import 'widgets/auth_glass_form_panel.dart';

/// Desktop: split brand panel + card. Mobile: full-screen photo, scrim, frosted form.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _logoAsset = 'assets/images/app_logo.png';
  static const _panelBgAsset = 'assets/auth/login_bg.png';

  /// Vertical rhythm for auth card (title → inputs → actions → footer).
  static const double _gapTitleToInput = 16;
  static const double _gapSection = 24;
  /// Input band: default spacing between fields (12–16).
  static const double _gapInputMin = 12;
  static const double _gapInput = 14;
  static const double _gapButton = 20;
  static const double _gapFooter = 24;
  /// Extra scroll padding below card content (beyond [SafeArea] insets).
  static const double _pageBottomPad = 16;
  /// Extra space when scrolling focused fields above the keyboard.
  static const EdgeInsets _fieldScrollPadding = EdgeInsets.only(bottom: 100);

  final _loginEmail = TextEditingController();
  final _loginPass = TextEditingController();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();

  final _authScrollController = ScrollController();
  final _emailFieldKey = GlobalKey();
  final _passwordFieldKey = GlobalKey();

  late final AnimationController _cardAnim;
  late final Animation<double> _cardFade;

  bool _loading = false;
  bool _obscure = true;
  bool _showValidation = false;
  bool _buttonPressed = false;
  bool _logoPrecached = false;
  bool _didRedirectSignup = false;
  bool _handledDupEmailQuery = false;
  Size? _lastViewPhysicalSize;

  /// Split layout (left hero / right card) at this width and above.
  static const double _desktopSplitMinWidth = 768;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cardAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _cardFade = CurvedAnimation(
      parent: _cardAnim,
      curve: Curves.easeOutCubic,
    );
    _loginEmail.addListener(() => setState(() {}));
    _loginPass.addListener(() => setState(() {}));
    _emailFocus.addListener(_onEmailFocusScroll);
    _passFocus.addListener(_onPasswordFocusScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cardAnim.forward();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryResumeSession());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_logoPrecached) {
      _logoPrecached = true;
      precacheImage(const AssetImage(_logoAsset), context);
      precacheImage(const AssetImage(_panelBgAsset), context);
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
    _emailFocus.removeListener(_onEmailFocusScroll);
    _passFocus.removeListener(_onPasswordFocusScroll);
    _authScrollController.dispose();
    _cardAnim.dispose();
    _loginEmail.dispose();
    _loginPass.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  void _onEmailFocusScroll() {
    if (_emailFocus.hasFocus) {
      _scrollFocusedFieldIntoView(_emailFieldKey);
    }
  }

  void _onPasswordFocusScroll() {
    if (_passFocus.hasFocus) {
      _scrollFocusedFieldIntoView(_passwordFieldKey);
    }
  }

  /// Scrolls the active [TextField] into view above the keyboard.
  void _scrollFocusedFieldIntoView(GlobalKey fieldKey) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = fieldKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.18,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
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
    if (!mounted) return;
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
        if (!mounted) return;
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

  InputDecoration _fieldDeco(
    String label,
    String hint,
    IconData icon, {
    bool err = false,
    Widget? suffix,
    double suffixMaxWidth = 64,
  }) {
    const radius = BorderRadius.all(Radius.circular(12));
    const normal = HexaOutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: HexaColors.inputBorderGrey, width: 1),
      focusRing: false,
    );
    final errorOutline = HexaOutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: Colors.red.shade600, width: 1.5),
      focusRing: false,
    );
    const focusOk = HexaOutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: HexaColors.brandAccent, width: 2.5),
      focusRing: true,
      ringColor: HexaColors.inputFocusRing,
    );
    final focusErr = HexaOutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: Colors.red.shade600, width: 2),
      focusRing: true,
      ringColor: HexaColors.inputErrorFocusRing,
    );
    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      hintText: hint,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.85),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      hintStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: HexaColors.inputHint,
      ),
      labelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: HexaColors.textOnLightSurface.withValues(alpha: 0.90),
      ),
      floatingLabelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: HexaColors.brandAccent,
      ),
      prefixIcon: Icon(icon, size: 22, color: HexaColors.textBody),
      prefixIconConstraints:
          const BoxConstraints(minWidth: 48, minHeight: 48),
      suffixIcon: suffix,
      suffixIconConstraints: suffix != null
          ? BoxConstraints(
              minWidth: 44,
              maxWidth: suffixMaxWidth,
              minHeight: 48,
              maxHeight: 52,
            )
          : null,
      border: err ? errorOutline : normal,
      enabledBorder: err ? errorOutline : normal,
      focusedBorder: err ? focusErr : focusOk,
      errorBorder: errorOutline,
      focusedErrorBorder: focusErr,
    );
  }

  Widget _err(String? m) {
    if (m == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4, bottom: 6),
      child: Text(
        m,
        maxLines: 4,
        softWrap: true,
        overflow: TextOverflow.visible,
        style: TextStyle(
          color: Colors.red.shade700,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// Text + logo stack for the auth hero (compact = mobile / narrow).
  Widget _brandPanelContent({required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: compact ? 48 : 56,
            height: compact ? 48 : 56,
            color: Colors.white,
            alignment: Alignment.center,
            child: Image.asset(
              _logoAsset,
              width: compact ? 40 : 48,
              height: compact ? 40 : 48,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
        SizedBox(height: compact ? 12 : 32),
        Text(
          AppConfig.appName,
          style: TextStyle(
            fontSize: compact ? 12 : 14,
            fontWeight: FontWeight.w700,
            letterSpacing: compact ? 0.5 : 0.6,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
        SizedBox(height: compact ? 4 : 12),
        Text(
          'Welcome back',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 22 : 34,
            fontWeight: FontWeight.w800,
            height: compact ? 1.05 : 1.1,
            letterSpacing: compact ? -0.6 : -0.8,
            color: Colors.white,
          ),
        ),
        SizedBox(height: compact ? 6 : 14),
        Text(
          'Manage your purchases smarter',
          maxLines: compact ? 2 : 4,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 13 : 17,
            fontWeight: FontWeight.w500,
            height: compact ? 1.22 : 1.45,
            color: Colors.white.withValues(alpha: 0.88),
          ),
        ),
      ],
    );
  }

  Widget _brandPanel({required bool compact}) {
    final imgAlign =
        compact ? Alignment.topCenter : const Alignment(0, -0.12);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Image.asset(
            _panelBgAsset,
            fit: BoxFit.cover,
            alignment: imgAlign,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF0A3D36).withValues(alpha: 0.90),
                  HexaColors.brandPrimary.withValues(alpha: 0.84),
                  const Color(0xFF0F5C52).withValues(alpha: 0.82),
                  HexaColors.brandAccent.withValues(alpha: 0.78),
                ],
                stops: const [0.0, 0.35, 0.72, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          right: -40,
          top: -20,
          child: Icon(
            Icons.show_chart_rounded,
            size: compact ? 80 : 200,
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 40,
            vertical: compact ? 14 : 48,
          ),
          child: compact
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topLeft,
                  child: _brandPanelContent(compact: true),
                )
              : _brandPanelContent(compact: false),
        ),
      ],
    );
  }

  List<Widget> _loginFormFields(BuildContext context, {required bool showGoogle}) {
    final eErr = _emailError();
    final pErr = _passError();
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              'Sign In',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: HexaColors.inputText,
                    letterSpacing: -0.3,
                    height: 1.15,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextButton(
              onPressed: _loading
                  ? null
                  : () {
                      FocusScope.of(context).unfocus();
                      context.go('/signup');
                    },
              style: TextButton.styleFrom(
                foregroundColor: HexaColors.brandAccent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                minimumSize: const Size(48, 44),
                tapTargetSize: MaterialTapTargetSize.padded,
                alignment: Alignment.centerRight,
              ),
              child: const Text(
                'Create account',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: _gapTitleToInput),
      TextField(
        controller: _loginEmail,
        focusNode: _emailFocus,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        scrollPadding: _fieldScrollPadding,
        autofillHints: const [AutofillHints.email],
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: HexaColors.inputText,
        ),
        onSubmitted: (_) => _passFocus.requestFocus(),
        decoration: _fieldDeco(
          'Work email',
          'you@company.com',
          Icons.mail_outline_rounded,
          err: eErr != null,
        ),
      ),
      _err(eErr),
      const SizedBox(height: _gapInput),
      KeyedSubtree(
        key: _passwordFieldKey,
        child: TextField(
          controller: _loginPass,
          focusNode: _passFocus,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          scrollPadding: _fieldScrollPadding,
          autofillHints: const [AutofillHints.password],
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: HexaColors.inputText,
          ),
          onSubmitted: (_) => _signIn(),
          decoration: _fieldDeco(
            'Password',
            'Enter your password',
            Icons.lock_outline_rounded,
            err: pErr != null,
            suffix: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.all(8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: HexaColors.textBody,
                size: 22,
              ),
            ),
          ),
        ),
      ),
      _err(pErr),
      const SizedBox(height: _gapInputMin),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _loading ? null : _forgotPassword,
          style: TextButton.styleFrom(
            foregroundColor: HexaColors.brandAccent,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            minimumSize: const Size(48, 44),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          child: const Text(
            'Forgot password?',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
      const SizedBox(height: _gapButton),
      Listener(
        onPointerDown: (_) {
          if (!_loading && mounted) {
            setState(() => _buttonPressed = true);
          }
        },
        onPointerUp: (_) {
          if (mounted) setState(() => _buttonPressed = false);
        },
        onPointerCancel: (_) {
          if (mounted) setState(() => _buttonPressed = false);
        },
        child: AnimatedScale(
          scale: (_buttonPressed && !_loading) ? 0.97 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: _LoginGradientCta(
            label: 'Sign In',
            busy: _loading,
            onTap: () {
              if (_loading) return;
              if (!_isFormValid) {
                setState(() => _showValidation = true);
                return;
              }
              _signIn();
            },
          ),
        ),
      ),
      if (showGoogle) ...[
        const SizedBox(height: _gapSection),
        const Row(
          children: [
            Expanded(child: Divider(color: HexaColors.brandBorder)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'or',
                style: TextStyle(
                  fontSize: 13,
                  color: HexaColors.textOnLightSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(child: Divider(color: HexaColors.brandBorder)),
          ],
        ),
        const SizedBox(height: _gapInput),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: _loading ? null : _googleSignIn,
            style: OutlinedButton.styleFrom(
              foregroundColor: HexaColors.textOnLightSurface,
              backgroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              side: const BorderSide(color: HexaColors.brandBorder, width: 1.25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
              shadowColor: Colors.transparent,
            ),
            child: const Text(
              'Continue with Google',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
      const SizedBox(height: _gapFooter),
      Text(
        '${AppConfig.appName} © 2026',
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: HexaColors.textOnLightSurface.withValues(alpha: 0.88),
          fontWeight: FontWeight.w600,
        ),
      ),
    ];
  }

  /// Mobile-only: branding over full-screen hero (no duplicate image card).
  Widget _loginMobileBrandingHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.asset(
            _logoAsset,
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Welcome back',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            height: 1.12,
            letterSpacing: -0.5,
            color: Colors.white,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.55),
                offset: const Offset(0, 2),
                blurRadius: 14,
              ),
              Shadow(
                color: Colors.black.withValues(alpha: 0.35),
                offset: const Offset(0, 1),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Manage your purchases smarter',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            height: 1.4,
            color: Colors.white.withValues(alpha: 0.95),
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.45),
                offset: const Offset(0, 1),
                blurRadius: 10,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Full-screen background + frosted form (mobile + keyboard-open).
  Widget _buildMobileAuthScaffold(BuildContext context,
      {required bool showGoogle}) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Image.asset(
                _panelBgAsset,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.black.withValues(alpha: 0.35),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final keyboardBottom =
                        MediaQuery.viewInsetsOf(context).bottom + 20;
                    return SingleChildScrollView(
                      controller: _authScrollController,
                      physics: const ClampingScrollPhysics(),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      clipBehavior: Clip.hardEdge,
                      padding: EdgeInsets.only(bottom: keyboardBottom),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: FadeTransition(
                          opacity: _cardFade,
                          child: Form(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: _loginMobileBrandingHeader(),
                                ),
                                const SizedBox(height: 18),
                                AuthGlassFormPanel(
                                  child: AutofillGroup(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: _loginFormFields(
                                        context,
                                        showGoogle: showGoogle,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loginCard(
    BuildContext context, {
    required bool showGoogle,
    bool compactPadding = false,
  }) {
    final inset = compactPadding
        ? const EdgeInsets.all(20)
        : const EdgeInsets.symmetric(horizontal: 24, vertical: 20);
    return FadeTransition(
      opacity: _cardFade,
      child: AuthGlassFormPanel(
        padding: inset,
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _loginFormFields(context, showGoogle: showGoogle),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showGoogle = AppConfig.googleOAuthClientId.isNotEmpty;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final w = MediaQuery.sizeOf(context).width;

    if (inset > 8) {
      return _buildMobileAuthScaffold(context, showGoogle: showGoogle);
    }

    if (w >= _desktopSplitMinWidth) {
      return Scaffold(
        backgroundColor: const Color(0xFFF1F5F4),
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => FocusScope.of(context).unfocus(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 11,
                  child: _brandPanel(compact: false),
                ),
                Expanded(
                  flex: 9,
                  child: Center(
                    child: SingleChildScrollView(
                      controller: _authScrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      clipBehavior: Clip.hardEdge,
                      padding: EdgeInsets.fromLTRB(
                        24,
                        32,
                        24,
                        32 + _pageBottomPad + inset,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: _loginCard(context, showGoogle: showGoogle),
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

    return _buildMobileAuthScaffold(context, showGoogle: showGoogle);
  }
}

class _LoginGradientCta extends StatelessWidget {
  const _LoginGradientCta({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

  static List<BoxShadow> get _ctaShadow => [
        BoxShadow(
          color: HexaColors.brandPrimary.withValues(alpha: 0.32),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.white.withValues(alpha: 0.22),
          highlightColor: Colors.white.withValues(alpha: 0.1),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: HexaColors.ctaGradient,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.28),
                width: 1,
              ),
              boxShadow: _ctaShadow,
            ),
            child: Opacity(
              opacity: busy ? 0.88 : 1,
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
