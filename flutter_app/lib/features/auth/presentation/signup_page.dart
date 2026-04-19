import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/theme/hexa_outline_input_border.dart';
import 'widgets/auth_glass_form_panel.dart';

/// Desktop: split brand + card. Mobile: full-screen photo, scrim, frosted form.
class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _logoAsset = 'assets/images/app_logo.png';
  static const _panelBgAsset = 'assets/auth/signup_bg.png';

  static const double _desktopSplitMinWidth = 768;

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

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();

  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();
  final _pass2Focus = FocusNode();

  final _authScrollController = ScrollController();
  final _nameFieldKey = GlobalKey();
  final _emailFieldKey = GlobalKey();
  final _passwordFieldKey = GlobalKey();
  final _confirmPasswordFieldKey = GlobalKey();

  late final AnimationController _cardAnim;
  late final Animation<double> _cardFade;

  bool _showValidation = false;
  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _buttonPressed = false;
  String? _apiError;
  bool _logoPrecached = false;
  Size? _lastViewPhysicalSize;

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
    for (final c in [_nameCtrl, _emailCtrl, _passCtrl, _pass2Ctrl]) {
      c.addListener(() {
        if (mounted) {
          setState(() => _apiError = null);
        }
      });
    }
    _nameFocus.addListener(_onNameFocusScroll);
    _emailFocus.addListener(_onSignupEmailFocusScroll);
    _passFocus.addListener(_onSignupPasswordFocusScroll);
    _pass2Focus.addListener(_onConfirmPasswordFocusScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cardAnim.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_logoPrecached) {
      _logoPrecached = true;
      precacheImage(const AssetImage(_logoAsset), context);
      precacheImage(const AssetImage(_panelBgAsset), context);
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
    _nameFocus.removeListener(_onNameFocusScroll);
    _emailFocus.removeListener(_onSignupEmailFocusScroll);
    _passFocus.removeListener(_onSignupPasswordFocusScroll);
    _pass2Focus.removeListener(_onConfirmPasswordFocusScroll);
    _authScrollController.dispose();
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

  void _onNameFocusScroll() {
    if (_nameFocus.hasFocus) _scrollFocusedFieldIntoView(_nameFieldKey);
  }

  void _onSignupEmailFocusScroll() {
    if (_emailFocus.hasFocus) _scrollFocusedFieldIntoView(_emailFieldKey);
  }

  void _onSignupPasswordFocusScroll() {
    if (_passFocus.hasFocus) _scrollFocusedFieldIntoView(_passwordFieldKey);
  }

  void _onConfirmPasswordFocusScroll() {
    if (_pass2Focus.hasFocus) {
      _scrollFocusedFieldIntoView(_confirmPasswordFieldKey);
    }
  }

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

  bool _nameOk() => _nameCtrl.text.trim().isNotEmpty;

  bool _emailOk() {
    final s = _emailCtrl.text.trim();
    return s.isNotEmpty && _emailValid(s);
  }

  bool _passStrongOk() =>
      _passCtrl.text.length >= 8 &&
      _passwordStrengthScore(_passCtrl.text) >= 4;

  bool _pass2Ok() {
    final p = _passCtrl.text;
    final p2 = _pass2Ctrl.text;
    return p2.isNotEmpty && p.length >= 8 && p == p2;
  }

  /// Score used for strength meter (0–5).
  int _passwordStrengthScore(String p) {
    if (p.isEmpty) return 0;
    var s = 0;
    if (p.length >= 8) s++;
    if (p.length >= 12) s++;
    if (RegExp(r'[a-z]').hasMatch(p)) s++;
    if (RegExp(r'[A-Z]').hasMatch(p)) s++;
    if (RegExp(r'\d').hasMatch(p)) s++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) s++;
    return s.clamp(0, 5);
  }

  String _passwordStrengthLabel(int score) {
    if (score <= 1) return 'Weak';
    if (score <= 3) return 'Medium';
    return 'Strong';
  }

  Color _passwordStrengthColor(int score) {
    if (score <= 1) return const Color(0xFFDC2626);
    if (score <= 3) return const Color(0xFFD97706);
    return const Color(0xFF059669);
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
      labelStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: HexaColors.textOnLightSurface,
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

  Widget _suffixSuccessCheck(bool show) {
    if (!show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Icon(
        Icons.check_circle_rounded,
        size: 22,
        color: Colors.green.shade600,
      ),
    );
  }

  Widget _passwordStrengthBlock() {
    final p = _passCtrl.text;
    final hint = 'Use 8+ characters with letters, numbers, and symbols.';
    if (p.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(
          hint,
          style: const TextStyle(
            fontSize: 12,
            height: 1.35,
            color: HexaColors.textBody,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    final score = _passwordStrengthScore(p);
    final label = _passwordStrengthLabel(score);
    final color = _passwordStrengthColor(score);
    final t = (score / 5).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(top: _gapInputMin, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Password strength: ',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: HexaColors.textOnLightSurface,
                ),
              ),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: _gapInputMin),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: t,
              minHeight: 6,
              backgroundColor: HexaColors.brandBorder,
              color: color,
            ),
          ),
          const SizedBox(height: _gapInputMin),
          Text(
            hint,
            style: const TextStyle(
              fontSize: 11,
              height: 1.35,
              color: HexaColors.textBody,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: HexaColors.textBody,
        ),
      ),
    );
  }

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
          'Create your account',
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
          'Manage your purchases smarter from day one',
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
            Icons.person_add_alt_1_rounded,
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

  List<Widget> _signupFormFields(BuildContext context) {
    final nameErr = _nameError();
    final emailErr = _emailError();
    final passErr = _passError();
    final pass2Err = _pass2Error();

    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              'Create account',
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
                      context.go('/login');
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
                'Sign In',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: _gapTitleToInput),
      _sectionLabel('Your profile'),
      KeyedSubtree(
        key: _nameFieldKey,
        child: TextField(
          controller: _nameCtrl,
          focusNode: _nameFocus,
          textInputAction: TextInputAction.next,
          scrollPadding: _fieldScrollPadding,
          autofillHints: const [AutofillHints.name],
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: HexaColors.inputText,
          ),
          onSubmitted: (_) => _emailFocus.requestFocus(),
          decoration: _fieldDeco(
            'Full name',
            'Jane Doe',
            Icons.person_outline_rounded,
            err: nameErr != null,
            suffix: _suffixSuccessCheck(_nameOk()),
          ),
        ),
      ),
      _err(nameErr),
      const SizedBox(height: _gapInput),
      KeyedSubtree(
        key: _emailFieldKey,
        child: TextField(
          controller: _emailCtrl,
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
            err: emailErr != null,
            suffix: _suffixSuccessCheck(_emailOk()),
          ),
        ),
      ),
      _err(emailErr),
      const SizedBox(height: _gapSection),
      _sectionLabel('Security'),
      KeyedSubtree(
        key: _passwordFieldKey,
        child: TextField(
          controller: _passCtrl,
          focusNode: _passFocus,
          obscureText: _obscure1,
          textInputAction: TextInputAction.next,
          scrollPadding: _fieldScrollPadding,
          autofillHints: const [AutofillHints.newPassword],
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: HexaColors.inputText,
          ),
          onSubmitted: (_) => _pass2Focus.requestFocus(),
          decoration: _fieldDeco(
            'Password',
            'Create a strong password',
            Icons.lock_outline_rounded,
            err: passErr != null,
            suffixMaxWidth: 128,
            suffix: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _suffixSuccessCheck(_passStrongOk()),
                IconButton(
                  tooltip: _obscure1 ? 'Show password' : 'Hide password',
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.all(8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => setState(() => _obscure1 = !_obscure1),
                  icon: Icon(
                    _obscure1
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: HexaColors.textBody,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      _err(passErr),
      _passwordStrengthBlock(),
      const SizedBox(height: _gapInput),
      KeyedSubtree(
        key: _confirmPasswordFieldKey,
        child: TextField(
          controller: _pass2Ctrl,
          focusNode: _pass2Focus,
          obscureText: _obscure2,
          textInputAction: TextInputAction.done,
          scrollPadding: _fieldScrollPadding,
          autofillHints: const [AutofillHints.newPassword],
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: HexaColors.inputText,
          ),
          onSubmitted: (_) => _submit(),
          decoration: _fieldDeco(
            'Confirm password',
            'Re-enter your password',
            Icons.lock_person_outlined,
            err: pass2Err != null,
            suffixMaxWidth: 128,
            suffix: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _suffixSuccessCheck(_pass2Ok()),
                IconButton(
                  tooltip: _obscure2 ? 'Show password' : 'Hide password',
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.all(8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => setState(() => _obscure2 = !_obscure2),
                  icon: Icon(
                    _obscure2
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: HexaColors.textBody,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      _err(pass2Err),
      if (_apiError != null) ...[
        const SizedBox(height: _gapInput),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            _apiError!,
            textAlign: TextAlign.center,
            maxLines: 8,
            softWrap: true,
            overflow: TextOverflow.visible,
            style: TextStyle(
              color: Colors.red.shade700,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
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
          child: _SignupGradientCta(
            label: 'Create account',
            busy: _loading,
            onTap: () {
              if (_loading) return;
              if (!_isFormValid) {
                setState(() => _showValidation = true);
                return;
              }
              _submit();
            },
          ),
        ),
      ),
      const SizedBox(height: _gapSection),
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 8,
        children: [
          Text(
            'Already have an account?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: HexaColors.textOnLightSurface.withValues(alpha: 0.92),
                ),
          ),
          TextButton(
            onPressed: _loading
                ? null
                : () {
                    FocusScope.of(context).unfocus();
                    context.go('/login');
                  },
            style: TextButton.styleFrom(
              foregroundColor: HexaColors.brandAccent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(48, 44),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            child: const Text(
              'Sign In',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: _gapFooter),
      Text(
        '${AppConfig.appName} © 2026',
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: HexaColors.textOnLightSurface.withValues(alpha: 0.94),
          fontWeight: FontWeight.w600,
        ),
      ),
    ];
  }

  Widget _signupMobileBrandingHeader() {
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
          'Create your account',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            height: 1.12,
            letterSpacing: -0.5,
            color: Colors.white,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.45),
                offset: const Offset(0, 1),
                blurRadius: 10,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Manage your purchases smarter from day one',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.4,
            color: Colors.white.withValues(alpha: 0.92),
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.4),
                offset: const Offset(0, 1),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileAuthScaffold(BuildContext context) {
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
                                  child: _signupMobileBrandingHeader(),
                                ),
                                const SizedBox(height: 18),
                                AuthGlassFormPanel(
                                  child: AutofillGroup(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: _signupFormFields(context),
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

  Widget _signupCard(BuildContext context, {bool compactPadding = false}) {
    final inset = compactPadding
        ? const EdgeInsets.all(20)
        : const EdgeInsets.symmetric(horizontal: 24, vertical: 20);
    return FadeTransition(
      opacity: _cardFade,
      child: AuthGlassFormPanel(
        padding: inset,
        child: Form(
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _signupFormFields(context),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final w = MediaQuery.sizeOf(context).width;

    if (inset > 8) {
      return _buildMobileAuthScaffold(context);
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
                        child: _signupCard(context),
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

    return _buildMobileAuthScaffold(context);
  }
}

class _SignupGradientCta extends StatelessWidget {
  const _SignupGradientCta({
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
