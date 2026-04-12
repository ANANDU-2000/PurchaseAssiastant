import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

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

  /// If the user landed here with saved tokens (e.g. deep link) but no in-memory session, restore once.
  Future<void> _tryResumeSession() async {
    final t = await ref.read(tokenStoreProvider).read();
    if (t.access == null || t.refresh == null) return;
    if (ref.read(sessionProvider) != null) {
      if (mounted) context.go('/home');
      return;
    }
    setState(() => _loading = true);
    await ref.read(sessionProvider.notifier).restore();
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
        setState(() => _error = 'Sign in failed. Check credentials and that the API is running at ${AppConfig.apiBaseUrl}.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignIn() async {
    final g = googleSignInIfConfigured();
    if (g == null) {
      setState(() => _error = 'Set GOOGLE_OAUTH_CLIENT_ID when building (and configure iOS URL scheme / Android SHA-1).');
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
        setState(() => _error = 'Google sign-in failed. Check GOOGLE_OAUTH_CLIENT_IDS on the API and your Google Cloud OAuth clients.');
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
        setState(() => _error = 'Could not create account. Email/username may be taken, or the API is unreachable.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final showGoogle = AppConfig.googleOAuthClientId.isNotEmpty;
    final inputTheme = InputDecorationTheme(
      filled: true,
      fillColor: HexaColors.surfaceMuted,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: HexaColors.primaryMid, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );

    return Scaffold(
      backgroundColor: HexaColors.primaryDeep,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tabH = (constraints.maxHeight * 0.52).clamp(340.0, 520.0);
            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - MediaQuery.paddingOf(context).vertical),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'H',
                            style: GoogleFonts.dmSerifDisplay(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: HexaColors.primaryDeep,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'HEXA',
                              style: GoogleFonts.dmSerifDisplay(
                                fontSize: 34,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                height: 1.05,
                              ),
                            ),
                            Text(
                              'Purchase Intelligence',
                              style: tt.titleSmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Material(
                        color: HexaColors.surfaceCard,
                        elevation: 10,
                        shadowColor: HexaColors.primaryDeep.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(24),
                        child: Theme(
                          data: Theme.of(context).copyWith(inputDecorationTheme: inputTheme),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TabBar(
                                controller: _tab,
                                labelColor: HexaColors.primaryMid,
                                unselectedLabelColor: HexaColors.textSecondary,
                                indicatorColor: HexaColors.primaryMid,
                                indicatorWeight: 3,
                                labelStyle: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                unselectedLabelStyle: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                tabs: const [
                                  Tab(text: 'Sign in'),
                                  Tab(text: 'Create account'),
                                ],
                              ),
                              SizedBox(
                                height: tabH,
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
                                    ),
                                  ],
                                ),
                              ),
                              if (showGoogle) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                                  child: Row(
                                    children: [
                                      Expanded(child: Divider(color: HexaColors.border.withValues(alpha: 0.9))),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        child: Text('or', style: tt.labelMedium?.copyWith(color: HexaColors.textSecondary)),
                                      ),
                                      Expanded(child: Divider(color: HexaColors.border.withValues(alpha: 0.9))),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                                  child: OutlinedButton.icon(
                                    onPressed: _loading ? null : _googleSignIn,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: HexaColors.textPrimary,
                                      side: BorderSide(color: HexaColors.border.withValues(alpha: 0.95)),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
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
                    const SizedBox(height: 28),
                    Text(
                      'HEXA © 2026',
                      textAlign: TextAlign.center,
                      style: tt.labelMedium?.copyWith(color: Colors.white.withValues(alpha: 0.45)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      AppConfig.apiBaseUrl,
                      textAlign: TextAlign.center,
                      style: tt.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.28)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SignInForm extends StatefulWidget {
  const _SignInForm({
    required this.tt,
    required this.emailCtrl,
    required this.passCtrl,
    required this.loading,
    required this.error,
    required this.onSubmit,
  });

  final TextTheme tt;
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final bool loading;
  final String? error;
  final VoidCallback onSubmit;

  @override
  State<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<_SignInForm> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      children: [
        TextField(
          controller: widget.emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          style: widget.tt.bodyLarge?.copyWith(color: HexaColors.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.mail_outline_rounded, color: HexaColors.primaryMid),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: widget.passCtrl,
          obscureText: _obscure,
          style: widget.tt.bodyLarge?.copyWith(color: HexaColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.key_rounded, color: HexaColors.primaryMid),
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: HexaColors.textSecondary),
            ),
          ),
          onSubmitted: (_) => widget.onSubmit(),
        ),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: widget.loading ? null : widget.onSubmit,
          style: FilledButton.styleFrom(
            backgroundColor: HexaColors.primaryMid,
            disabledBackgroundColor: HexaColors.primaryMid.withValues(alpha: 0.45),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: widget.loading
              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Sign in', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
  });

  final TextTheme tt;
  final TextEditingController userCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final TextEditingController pass2Ctrl;
  final bool loading;
  final String? error;
  final VoidCallback onSubmit;

  @override
  State<_SignUpForm> createState() => _SignUpFormState();
}

class _SignUpFormState extends State<_SignUpForm> {
  bool _obscure1 = true;
  bool _obscure2 = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      children: [
        TextField(
          controller: widget.userCtrl,
          autocorrect: false,
          style: widget.tt.bodyLarge?.copyWith(color: HexaColors.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Username',
            helperText: '3–64 chars: letters, numbers, underscore',
            prefixIcon: Icon(Icons.badge_outlined, color: HexaColors.primaryMid),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          style: widget.tt.bodyLarge?.copyWith(color: HexaColors.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.mail_outline_rounded, color: HexaColors.primaryMid),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.passCtrl,
          obscureText: _obscure1,
          style: widget.tt.bodyLarge?.copyWith(color: HexaColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Password',
            helperText: 'At least 8 characters',
            prefixIcon: const Icon(Icons.key_rounded, color: HexaColors.primaryMid),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscure1 = !_obscure1),
              icon: Icon(_obscure1 ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: HexaColors.textSecondary),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.pass2Ctrl,
          obscureText: _obscure2,
          style: widget.tt.bodyLarge?.copyWith(color: HexaColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Confirm password',
            prefixIcon: const Icon(Icons.key_off_outlined, color: HexaColors.primaryMid),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscure2 = !_obscure2),
              icon: Icon(_obscure2 ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: HexaColors.textSecondary),
            ),
          ),
          onSubmitted: (_) => widget.onSubmit(),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: widget.loading ? null : widget.onSubmit,
          style: FilledButton.styleFrom(
            backgroundColor: HexaColors.primaryMid,
            disabledBackgroundColor: HexaColors.primaryMid.withValues(alpha: 0.45),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: widget.loading
              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Create account', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ),
        if (widget.error != null) ...[
          const SizedBox(height: 14),
          Text(widget.error!, style: widget.tt.bodySmall?.copyWith(color: cs.error, fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }
}
