import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/google_sign_in_helper.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/hexa_colors.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> with SingleTickerProviderStateMixin {
  late final TabController _tab;

  final _loginEmail = TextEditingController();
  final _loginPass = TextEditingController();

  final _regUser = TextEditingController();
  final _regEmail = TextEditingController();
  final _regPass = TextEditingController();
  final _regPass2 = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryResumeSession());
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
    } catch (_) {
      // Timeout / offline — stay on login.
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (ref.read(sessionProvider) != null) {
      context.go('/home');
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    _loginEmail.dispose();
    _loginPass.dispose();
    _regUser.dispose();
    _regEmail.dispose();
    _regPass.dispose();
    _regPass2.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await ref.read(sessionProvider.notifier).login(
            email: _loginEmail.text.trim(),
            password: _loginPass.text,
          );
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyAuthError(e, context: AuthErrorContext.login));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignIn() async {
    final g = googleSignInIfConfigured();
    if (g == null) {
      setState(() {
        _error = kDebugMode
            ? 'Google sign-in needs OAuth setup in this build (see developer docs).'
            : 'Google sign-in is not available in this version of the app.';
      });
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final account = await g.signIn();
      if (account == null) {
        return;
      }
      final auth = await account.authentication;
      final id = auth.idToken;
      if (id == null) {
        throw StateError('No Google ID token');
      }
      await ref.read(sessionProvider.notifier).signInWithGoogle(idToken: id);
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyGoogleSignInError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signUp() async {
    if (_regPass.text != _regPass2.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await ref.read(sessionProvider.notifier).register(
            username: _regUser.text.trim(),
            email: _regEmail.text.trim(),
            password: _regPass.text,
          );
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyAuthError(e, context: AuthErrorContext.register));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? helper,
    Widget? prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      prefixIcon: prefix,
      suffixIcon: suffix,
      filled: true,
      fillColor: HexaColors.canvas,
      labelStyle: TextStyle(color: HexaColors.textSecondary),
      helperStyle: TextStyle(color: HexaColors.textSecondary.withValues(alpha: 0.9)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: HexaColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: HexaColors.accentBlue.withValues(alpha: 0.65), width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final showGoogle = AppConfig.googleOAuthClientId.isNotEmpty;

    return Scaffold(
      backgroundColor: HexaColors.canvas,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: HexaColors.canvas,
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.8),
                  radius: 1.2,
                  colors: [
                    HexaColors.accentPurple.withValues(alpha: 0.14),
                    HexaColors.accentBlue.withValues(alpha: 0.06),
                    HexaColors.canvas,
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: HexaColors.primaryLight,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: HexaColors.accentBlue.withValues(alpha: 0.35)),
                        boxShadow: HexaColors.glowShadow(HexaColors.accentPurple, blur: 22),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'H',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: HexaColors.accentBlue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppConfig.appName,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: HexaColors.textPrimary,
                            height: 1.05,
                          ),
                        ),
                        Text(
                          'Purchase Intelligence',
                          style: tt.titleSmall?.copyWith(
                            color: HexaColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      decoration: BoxDecoration(
                        color: HexaColors.surfaceCard,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                        border: Border(
                          top: BorderSide(color: HexaColors.accentPurple.withValues(alpha: 0.25)),
                        ),
                        boxShadow: HexaColors.cardShadow(context),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AnimatedBuilder(
                              animation: _tab,
                              builder: (context, _) {
                                return Row(
                                  children: [
                                    Expanded(
                                      child: _PillTab(
                                        label: 'Sign In',
                                        selected: _tab.index == 0,
                                        onTap: () => _tab.animateTo(0),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _PillTab(
                                        label: 'Create Account',
                                        selected: _tab.index == 1,
                                        onTap: () => _tab.animateTo(1),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: TabBarView(
                                controller: _tab,
                                children: [
                                  _SignInForm(
                                    tt: tt,
                                    emailCtrl: _loginEmail,
                                    passCtrl: _loginPass,
                                    loading: _loading,
                                    error: _error,
                                    onSubmit: _signIn,
                                    fieldDecoration: _fieldDecoration,
                                    gradientButtonLabel: 'Sign In',
                                  ),
                                  _SignUpForm(
                                    tt: tt,
                                    userCtrl: _regUser,
                                    emailCtrl: _regEmail,
                                    passCtrl: _regPass,
                                    pass2Ctrl: _regPass2,
                                    loading: _loading,
                                    error: _error,
                                    onSubmit: _signUp,
                                    fieldDecoration: _fieldDecoration,
                                  ),
                                ],
                              ),
                            ),
                            if (showGoogle) ...[
                          Row(
                            children: [
                              Expanded(child: Divider(color: HexaColors.border)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  '— or —',
                                  style: tt.labelMedium?.copyWith(color: HexaColors.textSecondary),
                                ),
                              ),
                              Expanded(child: Divider(color: HexaColors.border)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: _loading ? null : _googleSignIn,
                              style: OutlinedButton.styleFrom(
                                backgroundColor: HexaColors.surfaceElevated,
                                foregroundColor: HexaColors.textPrimary,
                                side: BorderSide(color: HexaColors.border),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                              label: const Text('Continue with Google'),
                            ),
                          ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${AppConfig.appName} © 2026',
                textAlign: TextAlign.center,
                style: tt.labelMedium?.copyWith(color: HexaColors.textSecondary.withValues(alpha: 0.7)),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 6),
                Text(
                  AppConfig.apiBaseUrl,
                  textAlign: TextAlign.center,
                  style: tt.labelSmall?.copyWith(color: HexaColors.textSecondary.withValues(alpha: 0.35)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PillTab extends StatelessWidget {
  const _PillTab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        splashColor: HexaColors.accentPurple.withValues(alpha: 0.12),
        highlightColor: HexaColors.accentPurple.withValues(alpha: 0.06),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? cs.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? cs.primary : HexaColors.border,
            ),
            boxShadow: selected ? HexaColors.glowShadow(cs.primary, blur: 14) : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: tt.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: selected ? cs.onPrimary : HexaColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

typedef _FieldDeco = InputDecoration Function({
  required String label,
  String? helper,
  Widget? prefix,
  Widget? suffix,
});

class _SignInForm extends StatefulWidget {
  const _SignInForm({
    required this.tt,
    required this.emailCtrl,
    required this.passCtrl,
    required this.loading,
    required this.error,
    required this.onSubmit,
    required this.fieldDecoration,
    required this.gradientButtonLabel,
  });

  final TextTheme tt;
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final bool loading;
  final String? error;
  final VoidCallback onSubmit;
  final _FieldDeco fieldDecoration;
  final String gradientButtonLabel;

  @override
  State<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<_SignInForm> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fd = widget.fieldDecoration;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        TextField(
          controller: widget.emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          style: widget.tt.bodyLarge?.copyWith(color: HexaColors.textPrimary),
          decoration: fd(
            label: 'Email',
            prefix: const Icon(Icons.mail_outline_rounded, color: HexaColors.accentBlue),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: widget.passCtrl,
          obscureText: _obscure,
          style: widget.tt.bodyLarge?.copyWith(color: HexaColors.textPrimary),
          decoration: fd(
            label: 'Password',
            prefix: const Icon(Icons.key_rounded, color: HexaColors.accentBlue),
            suffix: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: HexaColors.textSecondary,
              ),
            ),
          ),
          onSubmitted: (_) => widget.onSubmit(),
        ),
        const SizedBox(height: 22),
        _GradientCta(
          label: widget.gradientButtonLabel,
          loading: widget.loading,
          onPressed: widget.onSubmit,
        ),
        if (widget.error != null) ...[
          const SizedBox(height: 14),
          Text(widget.error!, style: widget.tt.bodySmall?.copyWith(color: cs.error, fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }
}

class _SignUpForm extends StatefulWidget {
  const _SignUpForm({
    required this.tt,
    required this.userCtrl,
    required this.emailCtrl,
    required this.passCtrl,
    required this.pass2Ctrl,
    required this.loading,
    required this.error,
    required this.onSubmit,
    required this.fieldDecoration,
  });

  final TextTheme tt;
  final TextEditingController userCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final TextEditingController pass2Ctrl;
  final bool loading;
  final String? error;
  final VoidCallback onSubmit;
  final _FieldDeco fieldDecoration;

  @override
  State<_SignUpForm> createState() => _SignUpFormState();
}

class _SignUpFormState extends State<_SignUpForm> {
  bool _obscure1 = true;
  bool _obscure2 = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fd = widget.fieldDecoration;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        TextField(
          controller: widget.userCtrl,
          autocorrect: false,
          style: widget.tt.bodyLarge?.copyWith(color: HexaColors.textPrimary),
          decoration: fd(
            label: 'Username',
            helper: '3–64 chars: letters, numbers, underscore',
            prefix: const Icon(Icons.badge_outlined, color: HexaColors.accentBlue),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          style: widget.tt.bodyLarge?.copyWith(color: HexaColors.textPrimary),
          decoration: fd(
            label: 'Email',
            prefix: const Icon(Icons.mail_outline_rounded, color: HexaColors.accentBlue),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.passCtrl,
          obscureText: _obscure1,
          style: widget.tt.bodyLarge?.copyWith(color: HexaColors.textPrimary),
          decoration: fd(
            label: 'Password',
            helper: 'At least 8 characters',
            prefix: const Icon(Icons.key_rounded, color: HexaColors.accentBlue),
            suffix: IconButton(
              onPressed: () => setState(() => _obscure1 = !_obscure1),
              icon: Icon(
                _obscure1 ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: HexaColors.textSecondary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.pass2Ctrl,
          obscureText: _obscure2,
          style: widget.tt.bodyLarge?.copyWith(color: HexaColors.textPrimary),
          decoration: fd(
            label: 'Confirm password',
            prefix: const Icon(Icons.key_off_outlined, color: HexaColors.accentBlue),
            suffix: IconButton(
              onPressed: () => setState(() => _obscure2 = !_obscure2),
              icon: Icon(
                _obscure2 ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: HexaColors.textSecondary,
              ),
            ),
          ),
          onSubmitted: (_) => widget.onSubmit(),
        ),
        const SizedBox(height: 20),
        _GradientCta(
          label: 'Create account',
          loading: widget.loading,
          onPressed: widget.onSubmit,
        ),
        if (widget.error != null) ...[
          const SizedBox(height: 14),
          Text(widget.error!, style: widget.tt.bodySmall?.copyWith(color: cs.error, fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }
}

class _GradientCta extends StatelessWidget {
  const _GradientCta({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: HexaColors.ctaGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: HexaColors.glowShadow(HexaColors.accentPurple, blur: 20),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: loading ? null : onPressed,
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Colors.white,
                        shadows: [Shadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 1))],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
