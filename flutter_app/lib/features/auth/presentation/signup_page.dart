import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/theme/hexa_colors.dart';
import 'widgets/auth_input_styles.dart';
import 'widgets/auth_network_error_banner.dart';
import 'widgets/auth_page_shell.dart';

/// Register — same keyboard-safe shell as login (no hero image).
class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();

  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();
  final _pass2Focus = FocusNode();

  bool _showValidation = false;
  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _showNetworkBanner = false;
  DioException? _lastNetworkError;
  String? _apiError;

  @override
  void initState() {
    super.initState();
    for (final c in [_nameCtrl, _emailCtrl, _passCtrl, _pass2Ctrl]) {
      c.addListener(() {
        if (mounted) setState(() => _apiError = null);
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    _pass2Focus.dispose();
    super.dispose();
  }

  bool _emailValid(String v) {
    final s = v.trim();
    return RegExp(r'^[\w.+-]+@[\w.-]+\.\w{2,}$').hasMatch(s);
  }

  bool get _isFormValid {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final p = _passCtrl.text;
    final p2 = _pass2Ctrl.text;
    if (name.isEmpty) return false;
    if (!_emailValid(email)) return false;
    if (p.length < 8) return false;
    if (p != p2) return false;
    return true;
  }

  String? _nameError() {
    if (!_showValidation) return null;
    if (_nameCtrl.text.trim().isEmpty) return 'Name is required';
    return null;
  }

  String? _emailError() {
    if (!_showValidation) return null;
    final s = _emailCtrl.text.trim();
    if (s.isEmpty) return 'Email is required';
    if (!_emailValid(s)) return 'Enter a valid email';
    return null;
  }

  String? _passError() {
    if (!_showValidation) return null;
    if (_passCtrl.text.isEmpty) return 'Password is required';
    if (_passCtrl.text.length < 8) return 'Password must be 8+ characters';
    return null;
  }

  String? _pass2Error() {
    if (!_showValidation) return null;
    if (_pass2Ctrl.text.isEmpty) return 'Confirm your password';
    if (_passCtrl.text != _pass2Ctrl.text) return 'Passwords do not match';
    return null;
  }

  String _deriveUsername(String email) {
    final normalized = email.trim().toLowerCase();
    var local = normalized.split('@').first;
    local = local.replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (local.isEmpty) local = 'user';
    if (local.length < 3) local = '${local}usr';
    final tag = _fnv1a32Tag(normalized);
    const sep = '_';
    final budget = 64 - sep.length - tag.length;
    final prefix =
        local.length <= budget ? local : local.substring(0, budget);
    final out = '$prefix$sep$tag';
    return out.length > 64 ? out.substring(0, 64) : out;
  }

  String _fnv1a32Tag(String input) {
    var h = 2166136261;
    for (final c in input.codeUnits) {
      h ^= c;
      h = (h * 16777619) & 0xFFFFFFFF;
    }
    return h.toRadixString(36);
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _showValidation = true;
      _apiError = null;
      _showNetworkBanner = false;
      _lastNetworkError = null;
    });
    if (!_isFormValid) return;

    setState(() => _loading = true);
    try {
      await ref.read(sessionProvider.notifier).register(
            username: _deriveUsername(_emailCtrl.text),
            email: _emailCtrl.text.trim(),
            password: _passCtrl.text,
            name: _nameCtrl.text.trim(),
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
      setState(() {
        _apiError = friendlyAuthError(e, context: AuthErrorContext.register);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _apiError = e is DioException
              ? friendlyAuthError(e, context: AuthErrorContext.register)
              : 'Something went wrong. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _retryNetwork() {
    setState(() {
      _showNetworkBanner = false;
      _lastNetworkError = null;
    });
    if (_isFormValid) {
      _submit();
    } else {
      setState(() => _showValidation = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nameErr = _nameError();
    final emailErr = _emailError();
    final passErr = _passError();
    final pass2Err = _pass2Error();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
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
                    const Text(
                      'Create Account',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: HexaColors.brandPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_showNetworkBanner)
                      AuthNetworkErrorBanner(
                        onRetry: _retryNetwork,
                        title: authUnreachableBannerTitle(_lastNetworkError),
                        detail: authServerUnreachableDetail(_lastNetworkError),
                      ),
                    TextField(
                      controller: _nameCtrl,
                      focusNode: _nameFocus,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      onSubmitted: (_) => _emailFocus.requestFocus(),
                      decoration: authFilledDecoration(
                        'Name',
                        icon: Icons.person_outline_rounded,
                        err: nameErr != null,
                      ),
                    ),
                    if (nameErr != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 4),
                        child: Text(
                          nameErr,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 12),
                    TextField(
                      controller: _emailCtrl,
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
                        err: emailErr != null,
                      ),
                    ),
                    if (emailErr != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 4),
                        child: Text(
                          emailErr,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 12),
                    TextField(
                      controller: _passCtrl,
                      focusNode: _passFocus,
                      obscureText: _obscure1,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      onSubmitted: (_) => _pass2Focus.requestFocus(),
                      decoration: authFilledDecoration(
                        'Password',
                        icon: Icons.key_rounded,
                        err: passErr != null,
                        suffix: IconButton(
                          tooltip: _obscure1 ? 'Show' : 'Hide',
                          onPressed: () => setState(() => _obscure1 = !_obscure1),
                          icon: Icon(
                            _obscure1
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: const Color(0xFF6B7280),
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                    if (passErr != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 4),
                        child: Text(
                          passErr,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(left: 4, top: 4),
                        child: Text(
                          'At least 8 characters',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pass2Ctrl,
                      focusNode: _pass2Focus,
                      obscureText: _obscure2,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      onSubmitted: (_) {
                        if (_isFormValid) _submit();
                      },
                      decoration: authFilledDecoration(
                        'Confirm Password',
                        icon: Icons.lock_outline_rounded,
                        err: pass2Err != null,
                        suffix: IconButton(
                          tooltip: _obscure2 ? 'Show' : 'Hide',
                          onPressed: () => setState(() => _obscure2 = !_obscure2),
                          icon: Icon(
                            _obscure2
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: const Color(0xFF6B7280),
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                    if (pass2Err != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 4),
                        child: Text(
                          pass2Err,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 12),
                    if (_apiError != null) ...[
                      Text(
                        _apiError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: _loading
                            ? null
                            : (_isFormValid
                                ? _submit
                                : () => setState(() => _showValidation = true)),
                        style: FilledButton.styleFrom(
                          backgroundColor: HexaColors.brandPrimary,
                          disabledBackgroundColor: HexaColors.brandDisabledBg,
                          disabledForegroundColor: HexaColors.brandDisabledText,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
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
                            : const Text(
                                'Create Account',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => context.go('/login'),
                      child: const Text(
                        'Already have account? Login',
                        style: TextStyle(
                          color: HexaColors.brandAccent,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
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
    );
  }
}
