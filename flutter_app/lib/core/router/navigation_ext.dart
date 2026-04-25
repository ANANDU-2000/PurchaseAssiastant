import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Web and deep links may leave the stack empty; [pop] then does nothing
/// without a [GoRouter] history entry. Use [popOrGo] to always leave the
/// screen (notably the system back/leading button).
extension SafeGoRouterPop on BuildContext {
  void popOrGo(String location) {
    if (canPop()) {
      pop();
    } else {
      go(location);
    }
  }
}
