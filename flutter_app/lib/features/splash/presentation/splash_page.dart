import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/hexa_colors.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> with SingleTickerProviderStateMixin {
  bool _busy = true;
  String? _error;

  late AnimationController _anim;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).restore().timeout(
            kIsWeb ? const Duration(seconds: 8) : const Duration(seconds: 25),
          );
    } catch (_) {
      // Timeout / offline — continue to token check below.
    }
    if (!mounted) return;
    final s = ref.read(sessionProvider);
    if (s != null) {
      context.go('/home');
      return;
    }
    ({String? access, String? refresh}) t;
    try {
      t = await ref.read(tokenStoreProvider).read();
    } catch (_) {
      if (mounted) context.go('/login');
      return;
    }
    if (t.access != null && t.refresh != null) {
      setState(() {
        _busy = false;
        _error =
            "We couldn't refresh your session. You're still signed in—check your connection and tap Retry.";
      });
      return;
    }
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: HexaColors.canvas,
      body: FadeTransition(
        opacity: _fade,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.65),
              radius: 1.15,
              colors: [
                HexaColors.accentPurple.withValues(alpha: 0.12),
                HexaColors.accentBlue.withValues(alpha: 0.05),
                HexaColors.canvas,
              ],
              stops: const [0.0, 0.4, 1.0],
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: HexaColors.primaryLight,
                      shape: BoxShape.circle,
                      border: Border.all(color: HexaColors.accentBlue.withValues(alpha: 0.4)),
                      boxShadow: HexaColors.glowShadow(HexaColors.accentPurple, blur: 18),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'H',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: HexaColors.accentBlue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    AppConfig.appName,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: HexaColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Purchase Intelligence',
                    style: tt.bodyMedium?.copyWith(
                      color: HexaColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_busy) const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  if (_error != null) ...[
                    const SizedBox(height: 20),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: tt.bodyMedium?.copyWith(
                        color: HexaColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _busy ? null : _boot,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('Use another account'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
