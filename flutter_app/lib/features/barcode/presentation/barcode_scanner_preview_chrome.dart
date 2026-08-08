import 'package:flutter/material.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';

/// Corner reticle over the camera preview.
class ScannerReticlePainter extends CustomPainter {
  ScannerReticlePainter({required this.color, this.confirmed = false});
  final Color color;
  final bool confirmed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = confirmed ? HexaColors.profit : color
      ..style = PaintingStyle.stroke
      ..strokeWidth = confirmed ? 4.0 : 3.0;

    const length = 16.0;
    const radius = 8.0;

    final pathTL = Path()
      ..moveTo(0, length)
      ..lineTo(0, radius)
      ..arcToPoint(const Offset(radius, 0), radius: const Radius.circular(radius))
      ..lineTo(length, 0);
    canvas.drawPath(pathTL, paint);

    final pathTR = Path()
      ..moveTo(size.width - length, 0)
      ..lineTo(size.width - radius, 0)
      ..arcToPoint(Offset(size.width, radius),
          radius: const Radius.circular(radius))
      ..lineTo(size.width, length);
    canvas.drawPath(pathTR, paint);

    final pathBL = Path()
      ..moveTo(0, size.height - length)
      ..lineTo(0, size.height - radius)
      ..arcToPoint(Offset(radius, size.height),
          radius: const Radius.circular(radius))
      ..lineTo(length, size.height);
    canvas.drawPath(pathBL, paint);

    final pathBR = Path()
      ..moveTo(size.width - length, size.height)
      ..lineTo(size.width - radius, size.height)
      ..arcToPoint(Offset(size.width, size.height - radius),
          radius: const Radius.circular(radius))
      ..lineTo(size.width, size.height - length);
    canvas.drawPath(pathBR, paint);
  }

  @override
  bool shouldRepaint(covariant ScannerReticlePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.confirmed != confirmed;
}

/// Camera / permission / gesture chrome for the scanner (mobile + desktop left).
class BarcodeScannerPreviewChrome extends StatelessWidget {
  const BarcodeScannerPreviewChrome({
    super.key,
    required this.height,
    required this.child,
    required this.decodePulse,
    this.lookingUp = false,
    this.lookupLabel,
  });

  final double height;
  final Widget child;
  final bool decodePulse;
  final bool lookingUp;
  final String? lookupLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          CustomPaint(
            painter: ScannerReticlePainter(
              color: theme.colorScheme.primary,
              confirmed: decodePulse,
            ),
          ),
          if (lookingUp)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                color: Colors.black54,
                padding: const EdgeInsets.all(HexaDsSpace.s1),
                child: Text(
                  lookupLabel == null
                      ? 'Looking up…'
                      : 'Looking up $lookupLabel…',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
