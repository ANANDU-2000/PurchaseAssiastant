import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/config/app_config.dart';

/// Left / top brand column: dark blue–purple gradient, copy, checks, motion.
class AuthBrandPanel extends StatefulWidget {
  const AuthBrandPanel({
    super.key,
    this.compact = false,
    this.accentLine,
  });

  final bool compact;

  /// Shown under the subtitle (e.g. signup motivational line).
  final String? accentLine;

  @override
  State<AuthBrandPanel> createState() => _AuthBrandPanelState();
}

class _AuthBrandPanelState extends State<AuthBrandPanel> with TickerProviderStateMixin {
  late final AnimationController _float;
  late final AnimationController _shapeDrift;

  static const _features = <String>[
    'Smart purchase tracking',
    'AI insights',
    'Expense analytics',
    'Real-time reports',
  ];

  @override
  void initState() {
    super.initState();
    _float = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat(reverse: true);
    _shapeDrift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 13),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shapeDrift.dispose();
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: Listenable.merge([_float, _shapeDrift]),
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_float.value);
          final u = Curves.easeInOut.transform(_shapeDrift.value);
          final drift = 14.0 * t;
          final w = MediaQuery.sizeOf(context).width;
          final h = MediaQuery.sizeOf(context).height;
          return Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF020617),
                      Color(0xFF0F172A),
                      Color(0xFF1E1B4B),
                      Color(0xFF312E81),
                    ],
                    stops: [0.0, 0.35, 0.72, 1.0],
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _MeshPainter(
                    opacity: 0.07 + 0.03 * t,
                  ),
                ),
              ),
              Positioned(
                top: -50 + drift,
                right: -70 + drift * 0.55,
                child: _glowBlob(180, const Color(0xFF6366F1), 0.28),
              ),
              Positioned(
                bottom: -40 - drift * 0.8,
                left: -60 - drift * 0.35,
                child: _glowBlob(220, const Color(0xFF7C3AED), 0.22),
              ),
              Positioned(
                top: 0.28 * MediaQuery.sizeOf(context).height,
                left: -30 + drift * 0.25,
                child: _glowBlob(140, const Color(0xFF2563EB), 0.18),
              ),
              Positioned(
                right: 12,
                bottom: 80,
                child: _glowBlob(90, const Color(0xFFA78BFA), 0.12),
              ),
              if (!widget.compact) ...[
                _floatingRRect(
                  left: w * 0.52,
                  top: h * 0.1,
                  width: 76,
                  height: 52,
                  dx: 5 * math.sin(u * math.pi * 2),
                  dy: 4 * math.cos(t * math.pi * 2),
                  angle: 0.2 + 0.04 * t,
                ),
                _floatingRRect(
                  left: w * 0.06,
                  top: h * 0.42,
                  width: 58,
                  height: 58,
                  dx: -4 * math.cos(u * math.pi * 2),
                  dy: 6 * math.sin(t * math.pi * 2),
                  angle: -0.35 + 0.03 * u,
                ),
                _floatingRRect(
                  left: w * 0.62,
                  top: h * 0.58,
                  width: 44,
                  height: 72,
                  dx: 3 * math.sin((t + u) * math.pi),
                  dy: -3 * math.cos((t - u) * math.pi),
                  angle: 0.12 + 0.02 * u,
                ),
              ],
              child!,
            ],
          );
        },
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              widget.compact ? 22 : 40,
              widget.compact ? 20 : 44,
              widget.compact ? 22 : 40,
              widget.compact ? 16 : 40,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _logoMark(compact: widget.compact),
                SizedBox(height: widget.compact ? 14 : 28),
                Text(
                  AppConfig.appName,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: widget.compact ? 22 : 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.12,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Purchase Intelligence Platform',
                  style: GoogleFonts.inter(
                    fontSize: widget.compact ? 14 : 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.78),
                    height: 1.4,
                  ),
                ),
                if (widget.accentLine != null && widget.accentLine!.trim().isNotEmpty) ...[
                  SizedBox(height: widget.compact ? 10 : 14),
                  Text(
                    widget.accentLine!.trim(),
                    style: GoogleFonts.inter(
                      fontSize: widget.compact ? 13 : 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.9),
                      height: 1.45,
                    ),
                  ),
                ],
                SizedBox(height: widget.compact ? 14 : 28),
                if (!widget.compact)
                  ..._features.map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _CheckFeature(text: line),
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in _features.take(3))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: _CheckFeature(text: line, dense: true),
                        ),
                    ],
                  ),
                const Spacer(),
                if (!widget.compact)
                  ExcludeSemantics(
                    child: Row(
                      children: [
                        Icon(
                          Icons.insights_outlined,
                          color: Colors.white.withValues(alpha: 0.32),
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          Icons.account_balance_wallet_outlined,
                          color: Colors.white.withValues(alpha: 0.26),
                          size: 21,
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          Icons.poll_outlined,
                          color: Colors.white.withValues(alpha: 0.22),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _floatingRRect({
    required double left,
    required double top,
    required double width,
    required double height,
    required double dx,
    required double dy,
    required double angle,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: Transform.rotate(
          angle: angle,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _glowBlob(double size, Color color, double opacity) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: opacity),
        ),
      ),
    );
  }

  Widget _logoMark({required bool compact}) {
    final s = compact ? 44.0 : 52.0;
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF6366F1).withValues(alpha: 0.45),
            const Color(0xFF7C3AED).withValues(alpha: 0.25),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        'H',
        style: GoogleFonts.plusJakartaSans(
          fontSize: compact ? 22 : 26,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _CheckFeature extends StatelessWidget {
  const _CheckFeature({required this.text, this.dense = false});

  final String text;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: dense ? 1 : 2),
          child: Icon(
            Icons.check_rounded,
            size: dense ? 18 : 22,
            color: const Color(0xFF34D399).withValues(alpha: 0.95),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: dense ? 13 : 15,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// Subtle diagonal mesh for depth.
class _MeshPainter extends CustomPainter {
  _MeshPainter({required this.opacity});

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const step = 48.0;
    for (double x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        p,
      );
    }

    final glow = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width * 0.75, size.height * 0.15),
        size.shortestSide * 0.45,
        [
          const Color(0xFF6366F1).withValues(alpha: 0.12),
          Colors.transparent,
        ],
      );
    canvas.drawRect(Offset.zero & size, glow);
  }

  @override
  bool shouldRepaint(covariant _MeshPainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}
