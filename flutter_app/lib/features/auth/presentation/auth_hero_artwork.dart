import 'package:flutter/material.dart';

/// Hero strip: full-bleed artwork (top-aligned) for a premium look; slight crop at sides/bottom is normal on tall phones.
class AuthHeroArtwork extends StatelessWidget {
  const AuthHeroArtwork({
    super.key,
    required this.assetPath,
    required this.height,
  });

  final String assetPath;
  final double height;

  /// Fallback while the image loads.
  static const letterbox = Color(0xFF0C3D36);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: height,
      child: ColoredBox(
        color: letterbox,
        child: LayoutBuilder(
          builder: (context, c) {
            return Image.asset(
              assetPath,
              width: c.maxWidth,
              height: c.maxHeight,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
            );
          },
        ),
      ),
    );
  }
}
