import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Optimized page transitions for Purchase Assistant
class HexaPageTransitions {
  /// Fast slide transition for navigation (220ms)
  static PageRoute<T> slideTransition<T>({
    required Widget page,
    required String name,
  }) {
    return PageRouteBuilder<T>(
      settings: RouteSettings(name: name),
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeOutCubic;

        final tween = Tween(begin: begin, end: end).chain(
          CurveTween(curve: curve),
        );

        return SlideTransition(
          position: animation.drive(tween),
          child: child,
        );
      },
    );
  }

  /// Instant transition for tab switches (no animation)
  static PageRoute<T> instantTransition<T>({
    required Widget page,
    required String name,
  }) {
    return PageRouteBuilder<T>(
      settings: RouteSettings(name: name),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) => page,
    );
  }

  /// Fade transition for dialogs (150ms)
  static PageRoute<T> fadeTransition<T>({
    required Widget page,
    required String name,
  }) {
    return PageRouteBuilder<T>(
      settings: RouteSettings(name: name),
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
    );
  }

  /// Scale transition for modals (200ms)
  static PageRoute<T> scaleTransition<T>({
    required Widget page,
    required String name,
  }) {
    return PageRouteBuilder<T>(
      settings: RouteSettings(name: name),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = 0.9;
        const end = 1.0;
        const curve = Curves.easeOutCubic;

        final tween = Tween(begin: begin, end: end).chain(
          CurveTween(curve: curve),
        );

        return ScaleTransition(
          scale: animation.drive(tween),
          child: child,
        );
      },
    );
  }
}

/// Extension for GoRouter to use optimized transitions
extension HexaGoRouterTransitions on GoRouter {
  /// Push with slide transition
  void pushSlide(BuildContext context, String location) {
    push(location);
  }

  /// Replace with instant transition
  void replaceInstant(BuildContext context, String location) {
    replace(location);
  }
}
