import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/google_sign_in_helper.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/config/app_config.dart';

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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 44, color: cs.primary),
                  const SizedBox(height: 12),
                  Text('HEXA', style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    'Create an account with username, email, and password. Sign in with email and password (or Google if configured).',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tab,
              tabs: const [
                Tab(text: 'Sign in'),
                Tab(text: 'Create account'),
              ],
            ),
            if (AppConfig.googleOAuthClientId.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _googleSignIn,
                  icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  label: const Text('Continue with Google'),
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _SignInForm(
                    cs: cs,
                    tt: tt,
                    emailCtrl: _loginEmail,
                    passCtrl: _loginPass,
                    loading: _loading,
                    error: _error,
                    onSubmit: _signIn,
                  ),
                  _SignUpForm(
                    cs: cs,
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'API: ${AppConfig.apiBaseUrl}',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignInForm extends StatelessWidget {
  const _SignInForm({
    required this.cs,
    required this.tt,
    required this.emailCtrl,
    required this.passCtrl,
    required this.loading,
    required this.error,
    required this.onSubmit,
  });

  final ColorScheme cs;
  final TextTheme tt;
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final bool loading;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.mail_outline_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            prefixIcon: Icon(Icons.key_rounded),
          ),
          onSubmitted: (_) => onSubmit(),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: loading ? null : onSubmit,
          child: loading
              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Sign in'),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(error!, style: tt.bodySmall?.copyWith(color: cs.error)),
        ],
      ],
    );
  }
}

class _SignUpForm extends StatelessWidget {
  const _SignUpForm({
    required this.cs,
    required this.tt,
    required this.userCtrl,
    required this.emailCtrl,
    required this.passCtrl,
    required this.pass2Ctrl,
    required this.loading,
    required this.error,
    required this.onSubmit,
  });

  final ColorScheme cs;
  final TextTheme tt;
  final TextEditingController userCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final TextEditingController pass2Ctrl;
  final bool loading;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        TextField(
          controller: userCtrl,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Username',
            helperText: '3–64 chars: letters, numbers, underscore',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.mail_outline_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            helperText: 'At least 8 characters',
            prefixIcon: Icon(Icons.key_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: pass2Ctrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Confirm password',
            prefixIcon: Icon(Icons.key_off_outlined),
          ),
          onSubmitted: (_) => onSubmit(),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: loading ? null : onSubmit,
          child: loading
              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create account'),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(error!, style: tt.bodySmall?.copyWith(color: cs.error)),
        ],
      ],
    );
  }
}
