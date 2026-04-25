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

/// Enter email → submit reset request (server responds uniformly for privacy).
class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _email = TextEditingController();
  final _focus = FocusNode();

  bool _loading = false;
  bool _showValidation = false;
  bool _showNetworkBanner = false;
  DioException? _lastNetworkError;
  String? _inlineError;
  bool _submittedOk = false;
  String? _devResetToken;

  @override
  void dispose() {
    _email.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _emailValid(String v) {
    final s = v.trim();
    return RegExp(r'^[\w.+-]+@[\w.-]+\.\w{2,}$').hasMatch(s);
  }

  String? _emailError() {
    if (!_showValidation) return null;
    final s = _email.text.trim();
    if (s.isEmpty) return 'Email is required';
    if (!_emailValid(s)) return 'Enter a valid email';
    return null;
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _showValidation = true;
      _inlineError = null;
      _submittedOk = false;
      _devResetToken = null;
    });
    final s = _email.text.trim();
    if (!_emailValid(s)) return;

    setState(() {
      _loading = true;
      _showNetworkBanner = false;
      _lastNetworkError = null;
    });
    try {
      final data =
          await ref.read(hexaApiProvider).requestPasswordReset(email: s);
      if (!mounted) return;
      final dev = data['dev_reset_token']?.toString();
      setState(() {
        _submittedOk = true;
        _inlineError = null;
        _devResetToken =
            (dev != null && dev.isNotEmpty) ? dev : null;
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
      setState(() {
        _inlineError = friendlyAuthError(e, context: AuthErrorContext.login);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _inlineError = 'Something went wrong. Please try again.';
        });
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
    final eErr = _emailError();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: HexaColors.brandPrimary,
        title: const Text(
          'Reset password',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: () => FocusScope.of(context).unfocus(),
        child: AuthPageShell(
          children: [
            AuthFormCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Forgot password?',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: HexaColors.brandPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your email. If an account exists, you will receive reset instructions.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_showNetworkBanner)
                    AuthNetworkErrorBanner(
                      onRetry: _retry,
                      title: authUnreachableBannerTitle(_lastNetworkError),
                      detail: authServerUnreachableDetail(_lastNetworkError),
                    ),
                  TextField(
                    controller: _email,
                    focusNode: _focus,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.email],
                    onSubmitted: (_) => _submit(),
                    decoration: authFilledDecoration(
                      'Email',
                      icon: Icons.mail_outline_rounded,
                      err: eErr != null,
                    ),
                  ),
                  if (eErr != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Text(
                        eErr,
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
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  if (_submittedOk) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle_outline,
                            color: Colors.green.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'If this email is registered, reset instructions will be sent. Check your inbox.',
                            style: TextStyle(
                              color: Colors.green.shade900,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_devResetToken != null && _devResetToken!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Development: use the button below to set a new password (email is not sent yet).',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade800,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: () {
                          context.go(
                            '/reset-password?token=${Uri.encodeQueryComponent(_devResetToken!)}',
                          );
                        },
                        child: const Text('Set new password (dev)'),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _loading
                          ? null
                          : () {
                              if (_email.text.trim().isEmpty) {
                                setState(() => _showValidation = true);
                                return;
                              }
                              _submit();
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: HexaColors.brandPrimary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFE5E7EB),
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
                              'Send reset link',
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
                        : () {
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go('/login');
                            }
                          },
                    child: const Text('Back to sign in'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
