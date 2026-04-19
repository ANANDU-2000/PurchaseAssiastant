import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/theme/hexa_colors.dart';
import 'auth_hero_artwork.dart';

/// Premium iOS-style signup: hero + bottom sheet card, teal brand, inline validation.
class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage>
    with SingleTickerProviderStateMixin {
  static const _heroAsset = 'assets/signup/signup.png';

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();

  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();
  final _pass2Focus = FocusNode();

  late final AnimationController _cardAnim;
  late final Animation<Offset> _cardSlide;

  bool _showValidation = false;
  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _buttonPressed = false;
  String? _apiError;
  bool _didPrecache = false;

  @override
  void initState() {
    super.initState();
    _cardAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _cardSlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _cardAnim, curve: Curves.easeOutCubic));
    for (final c in [_nameCtrl, _emailCtrl, _passCtrl, _pass2Ctrl]) {
      c.addListener(() {
        if (mounted) setState(() => _apiError = null);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cardAnim.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrecache) return;
    _didPrecache = true;
    precacheImage(const AssetImage(_heroAsset), context);
  }

  @override
  void dispose() {
    _cardAnim.dispose();
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

  /// Backend requires a unique username. The email local-part alone collides across domains
  /// (e.g. `john@gmail.com` vs `john@work.com`), which produced 409 and looked like "must login".
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

  /// Short stable tag from full email (FNV-1a 32-bit → base36), no extra packages.
  String _fnv1a32Tag(String input) {
    var h = 2166136261;
    for (final c in input.codeUnits) {
      h ^= c;
      h = (h * 16777619) & 0xFFFFFFFF;
    }
    return h.toRadixString(36);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _showValidation = true;
      _apiError = null;
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _apiError = friendlyAuthError(e, context: AuthErrorContext.register);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Single-layer field: OutlineInputBorder only — no Container border on top.
  Widget _fieldShell({required bool hasError, required Widget child}) {
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

  Widget _errorLine(String? msg) {
    if (msg == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 2),
      child: Text(
        msg,
        style: TextStyle(
          color: Colors.red.shade700,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  List<Widget> _signupFieldChildren(BuildContext context) {
    final nameErr = _nameError();
    final emailErr = _emailError();
    final passErr = _passError();
    final pass2Err = _pass2Error();
    return [
      _fieldShell(
        hasError: nameErr != null,
        child: TextField(
          controller: _nameCtrl,
          focusNode: _nameFocus,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          onSubmitted: (_) => _emailFocus.requestFocus(),
          decoration: _fieldDeco(
            'Name',
            Icons.person_outline_rounded,
            err: nameErr != null,
          ),
        ),
      ),
      _errorLine(nameErr),
      _fieldShell(
        hasError: emailErr != null,
        child: TextField(
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
          decoration: _fieldDeco(
            'Email',
            Icons.mail_outline_rounded,
            err: emailErr != null,
          ),
        ),
      ),
      _errorLine(emailErr),
      _fieldShell(
        hasError: passErr != null,
        child: TextField(
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
          decoration: _fieldDeco(
            'Password',
            Icons.key_rounded,
            err: passErr != null,
            suffix: IconButton(
              tooltip: _obscure1 ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscure1 = !_obscure1),
              icon: Icon(
                _obscure1
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: const Color(0xFF8E8E93),
                size: 22,
              ),
            ),
          ),
        ),
      ),
      _errorLine(passErr),
      if (passErr == null)
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'At least 8 characters',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      _fieldShell(
        hasError: pass2Err != null,
        child: TextField(
          controller: _pass2Ctrl,
          focusNode: _pass2Focus,
          obscureText: _obscure2,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          onSubmitted: (_) => _submit(),
          decoration: _fieldDeco(
            'Confirm Password',
            Icons.lock_outline_rounded,
            err: pass2Err != null,
            suffix: IconButton(
              tooltip: _obscure2 ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscure2 = !_obscure2),
              icon: Icon(
                _obscure2
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: const Color(0xFF8E8E93),
                size: 22,
              ),
            ),
          ),
        ),
      ),
      _errorLine(pass2Err),
      if (_apiError != null) ...[
        const SizedBox(height: 4),
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
              onPressed: _loading ? null : (_isFormValid ? _submit : null),
              style: FilledButton.styleFrom(
                backgroundColor: HexaColors.brandPrimary,
                disabledBackgroundColor: HexaColors.brandDisabledBg,
                disabledForegroundColor: HexaColors.brandDisabledText,
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
                  : const Text('Create Account'),
            ),
          ),
        ),
      ),
      TextButton(
        onPressed: _loading ? null : () => context.go('/login'),
        child: const Text(
          'Already have account? Login',
          style: TextStyle(
            color: HexaColors.brandAccent,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final heroH = h * 0.45;
    final cardH = h * 0.60;
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
                    const Text(
                      'Create Account',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: HexaColors.brandPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Start managing your purchases',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ..._signupFieldChildren(context),
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
            clipBehavior: Clip.none,
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
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                          child: AutofillGroup(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Create Account',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: HexaColors.brandPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Start managing your purchases',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Expanded(
                                  child: ListView(
                                    physics: const ClampingScrollPhysics(),
                                    padding: EdgeInsets.zero,
                                    children: _signupFieldChildren(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
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
