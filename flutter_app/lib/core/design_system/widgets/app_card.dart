import 'dart:ui';

import 'package:flutter/material.dart';

import '../hexa_ds_tokens.dart';
import '../hexa_glass_theme.dart';

/// Glass-style elevated surface — blur, frosted fill, tokenized radius.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: HexaDsRadii.card,
        clipBehavior: clipBehavior,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: hx.glassBlurSigma, sigmaY: hx.glassBlurSigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: hx.glassFill,
              borderRadius: HexaDsRadii.card,
              border: Border.all(color: hx.glassStroke, width: 1),
              boxShadow: hx.cardShadow,
            ),
            child: Padding(
              padding: padding ?? const EdgeInsets.all(HexaDsSpace.s3),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
