import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/google_sign_in_helper.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/config/app_config.dart';

/// Light, iOS-style palette for this screen only (main shell stays on dark theme).
abstract final class _AuthLight {
  static const bg = Color(0xFFF2F2F7);
  static const surface = Color(0xFFFFFFFF);
  static const input = Color(0xFFF2F2F7);
  static const label = Color(0xFF8E8E93);
  static const title = Color(0xFF000000);
  static const iosBlue = Color(0xFF007AFF);
  static const segmentTrack = Color(0xFFE5E5EA);
  static const error = Color(0xFFFF3B30);
  static const divider = Color(0xFFC6C6C8);
}

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  final _loginEmail = TextEditingController();
  final _loginPass = TextEditingController();

  final _regUser = TextEditingController();
  final _regEmail = TextEditingController();
  final _regPass = TextEditingController();
  final _regPass2 = TextEditingController();

  bool _loading = false;
  String? _error;

  TextStyle get _bodyStyle => GoogleFonts.inter(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        color: _AuthLight.title,
        height: 1.25,
      );

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
        setState(() =>
            _error = friendlyAuthError(e, context: AuthErrorContext.login));
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
        setState(() =>
            _error = friendlyAuthError(e, context: AuthErrorContext.register));
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
    const radius = BorderRadius.all(Radius.circular(12));
    return InputDecoration(
      labelText: label,
      helperText: helper,
      prefixIcon: prefix,
      suffixIcon: suffix,
      filled: true,
      fillColor: _AuthLight.input,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      labelStyle: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: _AuthLight.title,
      ),
      helperStyle: GoogleFonts.inter(
        fontSize: 12,
        height: 1.3,
        color: _AuthLight.label,
      ),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      border: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide:
            BorderSide(color: _AuthLight.iosBlue.withValues(alpha: 0.55), width: 1.2),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: _AuthLight.error, width: 0.8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showGoogle = AppConfig.googleOAuthClientId.isNotEmpty;

    return Scaffold(
      backgroundColor: _AuthLight.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _AuthLight.iosBlue,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'H',
                      style: GoogleFonts.inter(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppConfig.appName,
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: _AuthLight.title,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Purchase Intelligence',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            color: _AuthLight.label,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: _AuthLight.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 20,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _IosSegmentedControl(
                        tab: _tab,
                        labels: const ['Sign In', 'Create Account'],
                      ),
                      const SizedBox(height: 22),
                      Expanded(
                        child: TabBarView(
                          controller: _tab,
                          children: [
                            _SignInForm(
                              bodyStyle: _bodyStyle,
                              emailCtrl: _loginEmail,
                              passCtrl: _loginPass,
                              loading: _loading,
                              error: _error,
                              onSubmit: _signIn,
                              fieldDecoration: _fieldDecoration,
                              primaryLabel: 'Sign In',
                            ),
                            _SignUpForm(
                              bodyStyle: _bodyStyle,
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
                            const Expanded(
                                child: Divider(color: _AuthLight.divider)),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              child: Text(
                                'or',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: _AuthLight.label,
                                ),
                              ),
                            ),
                            const Expanded(
                                child: Divider(color: _AuthLight.divider)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: _loading ? null : _googleSignIn,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _AuthLight.title,
                              backgroundColor: _AuthLight.surface,
                              side: const BorderSide(color: _AuthLight.divider),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: Text(
                              'G',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                                color: _AuthLight.title,
                              ),
                            ),
                            label: Text(
                              'Continue with Google',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${AppConfig.appName} © 2026',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: _AuthLight.label,
                ),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 6),
                Text(
                  AppConfig.apiBaseUrl,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: _AuthLight.label.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IosSegmentedControl extends StatelessWidget {
  const _IosSegmentedControl({
    required this.tab,
    required this.labels,
  });

  final TabController tab;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: tab,
      builder: (context, _) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: _AuthLight.segmentTrack,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    child: _SegmentChip(
                      label: labels[i],
                      selected: tab.index == i,
                      onTap: () => tab.animateTo(i),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
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
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? _AuthLight.title : _AuthLight.label,
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
    required this.bodyStyle,
    required this.emailCtrl,
    required this.passCtrl,
    required this.loading,
    required this.error,
    required this.onSubmit,
    required this.fieldDecoration,
    required this.primaryLabel,
  });

  final TextStyle bodyStyle;
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final bool loading;
  final String? error;
  final VoidCallback onSubmit;
  final _FieldDeco fieldDecoration;
  final String primaryLabel;

  @override
  State<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<_SignInForm> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final fd = widget.fieldDecoration;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        TextField(
          controller: widget.emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          style: widget.bodyStyle,
          decoration: fd(
            label: 'Email',
            prefix: const Icon(Icons.mail_outline_rounded,
                color: _AuthLight.label, size: 22),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: widget.passCtrl,
          obscureText: _obscure,
          style: widget.bodyStyle,
          decoration: fd(
            label: 'Password',
            prefix: const Icon(Icons.key_rounded,
                color: _AuthLight.label, size: 22),
            suffix: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: _AuthLight.label,
              ),
            ),
          ),
          onSubmitted: (_) => widget.onSubmit(),
        ),
        const SizedBox(height: 24),
        _IosPrimaryButton(
          label: widget.primaryLabel,
          loading: widget.loading,
          onPressed: widget.onSubmit,
        ),
        if (widget.error != null) ...[
          const SizedBox(height: 16),
          _AuthInlineError(message: widget.error!),
        ],
      ],
    );
  }
}

class _SignUpForm extends StatefulWidget {
  const _SignUpForm({
    required this.bodyStyle,
    required this.userCtrl,
    required this.emailCtrl,
    required this.passCtrl,
    required this.pass2Ctrl,
    required this.loading,
    required this.error,
    required this.onSubmit,
    required this.fieldDecoration,
  });

  final TextStyle bodyStyle;
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
    final fd = widget.fieldDecoration;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        TextField(
          controller: widget.userCtrl,
          autocorrect: false,
          style: widget.bodyStyle,
          decoration: fd(
            label: 'Username',
            helper: '3–64 chars: letters, numbers, underscore',
            prefix: const Icon(Icons.badge_outlined,
                color: _AuthLight.label, size: 22),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: widget.emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          style: widget.bodyStyle,
          decoration: fd(
            label: 'Email',
            prefix: const Icon(Icons.mail_outline_rounded,
                color: _AuthLight.label, size: 22),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: widget.passCtrl,
          obscureText: _obscure1,
          style: widget.bodyStyle,
          decoration: fd(
            label: 'Password',
            helper: 'At least 8 characters',
            prefix: const Icon(Icons.key_rounded,
                color: _AuthLight.label, size: 22),
            suffix: IconButton(
              onPressed: () => setState(() => _obscure1 = !_obscure1),
              icon: Icon(
                _obscure1
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: _AuthLight.label,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: widget.pass2Ctrl,
          obscureText: _obscure2,
          style: widget.bodyStyle,
          decoration: fd(
            label: 'Confirm password',
            prefix: const Icon(Icons.key_off_outlined,
                color: _AuthLight.label, size: 22),
            suffix: IconButton(
              onPressed: () => setState(() => _obscure2 = !_obscure2),
              icon: Icon(
                _obscure2
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: _AuthLight.label,
              ),
            ),
          ),
          onSubmitted: (_) => widget.onSubmit(),
        ),
        const SizedBox(height: 22),
        _IosPrimaryButton(
          label: 'Create account',
          loading: widget.loading,
          onPressed: widget.onSubmit,
        ),
        if (widget.error != null) ...[
          const SizedBox(height: 16),
          _AuthInlineError(message: widget.error!),
        ],
      ],
    );
  }
}

class _AuthInlineError extends StatelessWidget {
  const _AuthInlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        fontSize: 13,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: _AuthLight.error.withValues(alpha: 0.92),
      ),
    );
  }
}

class _IosPrimaryButton extends StatelessWidget {
  const _IosPrimaryButton({
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
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _AuthLight.iosBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _AuthLight.iosBlue.withValues(alpha: 0.45),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: loading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}
