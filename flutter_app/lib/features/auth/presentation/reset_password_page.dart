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

/// Complete password reset using `?token=` from email (or dev flow).
class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key, this.initialToken});

  final String? initialToken;

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  late final TextEditingController _pass;
  late final TextEditingController _pass2;
  final _passFocus = FocusNode();
  final _pass2Focus = FocusNode();

  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _loading = false;
  bool _showValidation = false;
  bool _showNetworkBanner = false;
  DioException? _lastNetworkError;
  String? _inlineError;
  String? _success;

  @override
  void initState() {
    super.initState();
    _pass = TextEditingController();
    _pass2 = TextEditingController();
  }

  @override
  void dispose() {
    _pass.dispose();
    _pass2.dispose();
    _passFocus.dispose();
    _pass2Focus.dispose();
    super.dispose();
  }

  String get _token => (widget.initialToken ?? '').trim();

  bool get _isFormValid {
    final a = _pass.text;
    final b = _pass2.text;
    return a.length >= 8 && a == b;
  }

  String? _passError() {
    if (!_showValidation) return null;
    if (_pass.text.isEmpty) return 'Password is required';
    if (_pass.text.length < 8) return 'Use at least 8 characters';
    return null;
  }

  String? _pass2Error() {
    if (!_showValidation) return null;
    if (_pass2.text.isEmpty) return 'Confirm your password';
    if (_pass.text != _pass2.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _showValidation = true;
      _inlineError = null;
      _success = null;
      _showNetworkBanner = false;
      _lastNetworkError = null;
    });
    if (_token.isEmpty || !_isFormValid) return;

    setState(() => _loading = true);
    try {
      await ref.read(hexaApiProvider).resetPasswordWithToken(
            token: _token,
            newPassword: _pass.text,
          );
      if (!mounted) return;
      setState(() {
        _success = 'Password updated. You can sign in now.';
        _inlineError = null;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      if (isDioNoConnectionError(e)) {
        setState(() {
          _lastNetworkError = e;
          _showNetworkBanner = true;
        });
        return;
      }
      var msg = 'Could not reset password.';
      final data = e.response?.data;
      if (data is Map && data['detail'] is String) {
        msg = data['detail'] as String;
      } else if (e.message != null && e.message!.isNotEmpty) {
        msg = e.message!;
      }
      setState(() => _inlineError = msg);
    } catch (_) {
      if (mounted) {
        setState(() => _inlineError = 'Something went wrong. Try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _retry() {
    setState(() {
      _showNetworkBanner = false;
      _lastNetworkError = null;
    });
    _submit();
  }

  @override
  Widget build(BuildContext context) {
    if (_token.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: HexaColors.brandPrimary,
          title: const Text('Reset password'),
        ),
        body: AuthPageShell(
          children: [
            const AuthSmallLogo(),
            AuthFormCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Invalid link',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: HexaColors.brandPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Open the reset link from your email, or request a new one.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.go('/forgot-password'),
                    child: const Text('Request reset link'),
                  ),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Back to sign in'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final p1 = _passError();
    final p2 = _pass2Error();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: HexaColors.brandPrimary,
        title: const Text(
          'New password',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: () => FocusScope.of(context).unfocus(),
        child: AuthPageShell(
          children: [
            const AuthSmallLogo(),
            AuthFormCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Choose a new password',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: HexaColors.brandPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Use at least 8 characters.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  if (_showNetworkBanner)
                    AuthNetworkErrorBanner(
                      onRetry: _retry,
                      title: authUnreachableBannerTitle(_lastNetworkError),
                      detail: authServerUnreachableDetail(_lastNetworkError),
                    ),
                  TextField(
                    controller: _pass,
                    focusNode: _passFocus,
                    obscureText: _obscure1,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
                    onSubmitted: (_) => _pass2Focus.requestFocus(),
                    decoration: authFilledDecoration(
                      'New password',
                      icon: Icons.key_rounded,
                      err: p1 != null,
                      suffix: IconButton(
                        onPressed: () => setState(() => _obscure1 = !_obscure1),
                        icon: Icon(
                          _obscure1
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ),
                  if (p1 != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Text(
                        p1,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass2,
                    focusNode: _pass2Focus,
                    obscureText: _obscure2,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    onSubmitted: (_) {
                      if (_isFormValid) _submit();
                    },
                    decoration: authFilledDecoration(
                      'Confirm password',
                      icon: Icons.lock_outline_rounded,
                      err: p2 != null,
                      suffix: IconButton(
                        onPressed: () => setState(() => _obscure2 = !_obscure2),
                        icon: Icon(
                          _obscure2
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ),
                  if (p2 != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Text(
                        p2,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  if (_inlineError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _inlineError!,
                      style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                    ),
                  ],
                  if (_success != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _success!,
                      style: TextStyle(color: Colors.green.shade800, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('Go to sign in'),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
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
                            : const Text('Update password'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
