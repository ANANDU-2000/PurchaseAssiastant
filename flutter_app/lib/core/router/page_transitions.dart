import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design_system/hexa_ds_tokens.dart';

/// Auth / marketing surfaces: gentle fade + micro vertical lift (minimal motion).
CustomTransitionPage<void> hexaAuthFadePage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: HexaDsMotion.authPage,
    reverseTransitionDuration: HexaDsMotion.authPageReverse,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: HexaDsMotion.enter,
        reverseCurve: HexaDsMotion.exit,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.028),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// iOS-style push: slide from right + short fade (full-screen routes only).
CustomTransitionPage<void> iosPushPage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: HexaDsMotion.pushPage,
    reverseTransitionDuration: HexaDsMotion.pushPageReverse,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: HexaDsMotion.enter,
        reverseCurve: HexaDsMotion.exit,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(
          opacity: curved,
          child: child,
        ),
      );
    },
  );
}
