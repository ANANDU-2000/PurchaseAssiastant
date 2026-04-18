import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/hexa_colors.dart';

/// Full-viewport landing: one hero image, dark gradient, single branding block at bottom.
///
/// Hero file: [flutter_app/assets/images/getstarted.png] — keep in sync with repo root
/// `getstartedimage/getstarted.png` (copy before release builds).
class GetStartedPage extends StatefulWidget {
  const GetStartedPage({super.key});

  @override
  State<GetStartedPage> createState() => _GetStartedPageState();
}

class _GetStartedPageState extends State<GetStartedPage>
    with SingleTickerProviderStateMixin {
  static const _heroAsset = 'assets/images/getstarted.png';
  static const _entryDuration = Duration(milliseconds: 700);
  static const _imageFadeDuration = Duration(milliseconds: 300);

  late final AnimationController _entryController;
  late final Animation<Offset> _contentSlide;
  late final Animation<double> _contentFade;
  late final Animation<double> _buttonScaleIn;
  bool _heroVisible = false;
  bool _didPrecache = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: _entryDuration,
    );
    _contentSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.1, 0.85, curve: Curves.easeOutCubic),
      ),
    );
    _contentFade = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.05, 0.75, curve: Curves.easeOut),
    );
    _buttonScaleIn = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.96, end: 1.02)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 65,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.02, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 35,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.5, 1.0),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _heroVisible = true);
      _entryController.forward();
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
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: AnimatedOpacity(
              duration: _imageFadeDuration,
              curve: Curves.easeOut,
              opacity: _heroVisible ? 1 : 0,
              child: Image.asset(
                _heroAsset,
                fit: BoxFit.cover,
                // Top-heavy art: anchor to top so skyline/emblem stay visible on tall narrow phones.
                alignment: Alignment.topCenter,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
                isAntiAlias: true,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    HexaColors.brandPrimary.withValues(alpha: 0.85),
                  ],
                  stops: const [0.35, 1.0],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              left: false,
              right: false,
              bottom: true,
              minimum: EdgeInsets.zero,
              child: FadeTransition(
                opacity: _contentFade,
                child: SlideTransition(
                  position: _contentSlide,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'New Harisree Agency',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Wholesale Rice, Grocery & Biriyani Items',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ScaleTransition(
                            scale: _buttonScaleIn,
                            child: _PremiumPrimaryButton(
                              text: 'GET STARTED',
                              onPressed: () => context.go('/signup'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => context.go('/login?tab=signin'),
                            style: TextButton.styleFrom(
                              foregroundColor: HexaColors.brandAccent,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            child: const Text(
                              'Already have account? Login',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
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
        ],
      ),
    );
  }
}

class _PremiumPrimaryButton extends StatefulWidget {
  const _PremiumPrimaryButton({
    required this.text,
    required this.onPressed,
  });

  final String text;
  final VoidCallback onPressed;

  @override
  State<_PremiumPrimaryButton> createState() => _PremiumPrimaryButtonState();
}

class _PremiumPrimaryButtonState extends State<_PremiumPrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const fill = HexaColors.brandPrimary;
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: Material(
          color: fill,
          borderRadius: BorderRadius.circular(14),
          elevation: 0,
          shadowColor: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            borderRadius: BorderRadius.circular(14),
            splashColor: Colors.white.withValues(alpha: 0.16),
            highlightColor: Colors.white.withValues(alpha: 0.06),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: fill.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  widget.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    letterSpacing: 0.3,
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
