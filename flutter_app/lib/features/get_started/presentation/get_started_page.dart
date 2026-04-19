import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/hexa_colors.dart';

/// Full-screen hero landing: cover photo, bottom-weighted scrim, top branding + bottom CTA.
class GetStartedPage extends StatefulWidget {
  const GetStartedPage({super.key});

  @override
  State<GetStartedPage> createState() => _GetStartedPageState();
}

class _GetStartedPageState extends State<GetStartedPage>
    with SingleTickerProviderStateMixin {
  static const _logoAsset = 'assets/images/app_logo.png';
  static const _bgAsset = 'assets/auth/login_bg.png';
  static const _entryDuration = Duration(milliseconds: 820);

  late final AnimationController _entryController;
  late final Animation<Offset> _contentSlide;
  late final Animation<double> _contentFade;
  late final Animation<double> _buttonScaleIn;
  bool _didPrecache = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: _entryDuration,
    );
    _contentSlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.08, 0.88, curve: Curves.easeOutCubic),
      ),
    );
    _contentFade = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
    );
    _buttonScaleIn = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.94, end: 1.02)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.02, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 45,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entryController.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrecache) return;
    _didPrecache = true;
    precacheImage(const AssetImage(_logoAsset), context);
    precacheImage(const AssetImage(_bgAsset), context);
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsetBottom = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.asset(
              _bgAsset,
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
                    Colors.black.withValues(alpha: 0.58),
                    Colors.black.withValues(alpha: 0.32),
                    Colors.black.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.32, 0.58, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    clipBehavior: Clip.hardEdge,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: FadeTransition(
                        opacity: _contentFade,
                        child: SlideTransition(
                          position: _contentSlide,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                alignment: Alignment.topCenter,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 44),
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 360),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        DecoratedBox(
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(18),
                                            border: Border.all(
                                              color: Colors.white
                                                  .withValues(alpha: 0.22),
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.35),
                                                blurRadius: 16,
                                                offset: const Offset(0, 6),
                                              ),
                                            ],
                                          ),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(17),
                                            child: Image.asset(
                                              _logoAsset,
                                              width: 68,
                                              height: 68,
                                              fit: BoxFit.cover,
                                              filterQuality: FilterQuality.high,
                                              gaplessPlayback: true,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        const Text(
                                          AppConfig.appName,
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.w800,
                                            height: 1.15,
                                            letterSpacing: -0.6,
                                            color: Colors.white,
                                            shadows: [
                                              Shadow(
                                                offset: Offset(0, 1),
                                                blurRadius: 12,
                                                color: Color(0x99000000),
                                              ),
                                              Shadow(
                                                offset: Offset(0, 2),
                                                blurRadius: 4,
                                                color: Color(0x66000000),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Purchase Intelligence for Smart Businesses',
                                          textAlign: TextAlign.center,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            height: 1.4,
                                            letterSpacing: 0.1,
                                            color: Colors.white
                                                .withValues(alpha: 0.95),
                                            shadows: const [
                                              Shadow(
                                                offset: Offset(0, 1),
                                                blurRadius: 10,
                                                color: Color(0x8C000000),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    top: 16,
                                    bottom: 28 + viewInsetBottom,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ScaleTransition(
                                        scale: _buttonScaleIn,
                                        child: _PremiumLandingCta(
                                          label: 'Get Started',
                                          onPressed: () =>
                                              context.go('/signup'),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TextButton(
                                        onPressed: () =>
                                            context.go('/login?tab=signin'),
                                        style: TextButton.styleFrom(
                                          foregroundColor:
                                              HexaColors.brandAccent,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                            horizontal: 12,
                                          ),
                                          minimumSize: const Size(48, 48),
                                          tapTargetSize:
                                              MaterialTapTargetSize.padded,
                                        ),
                                        child: const Text(
                                          'Already have an account? Sign In',
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            decoration:
                                                TextDecoration.underline,
                                            decorationColor:
                                                HexaColors.brandAccent,
                                            shadows: [
                                              Shadow(
                                                offset: Offset(0, 1),
                                                blurRadius: 8,
                                                color: Color(0xB3000000),
                                              ),
                                            ],
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
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumLandingCta extends StatefulWidget {
  const _PremiumLandingCta({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  State<_PremiumLandingCta> createState() => _PremiumLandingCtaState();
}

class _PremiumLandingCtaState extends State<_PremiumLandingCta> {
  bool _pressed = false;
  bool _hover = false;

  double get _scale {
    if (_pressed) return 0.97;
    if (_hover) return 1.01;
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _hover = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hover = false);
      },
      child: AnimatedScale(
        scale: _scale,
        duration: Duration(milliseconds: _pressed ? 90 : 140),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: Material(
            color: Colors.transparent,
            elevation: 0,
            child: InkWell(
              onTap: widget.onPressed,
              borderRadius: BorderRadius.circular(14),
              onTapDown: (_) {
                if (mounted) setState(() => _pressed = true);
              },
              onTapUp: (_) {
                if (mounted) setState(() => _pressed = false);
              },
              onTapCancel: () {
                if (mounted) setState(() => _pressed = false);
              },
              splashColor: Colors.white.withValues(alpha: 0.22),
              highlightColor: Colors.white.withValues(alpha: 0.10),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: HexaColors.ctaGradient,
                  boxShadow: [
                    BoxShadow(
                      color: HexaColors.brandPrimary.withValues(alpha: 0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      letterSpacing: 0.2,
                    ),
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
