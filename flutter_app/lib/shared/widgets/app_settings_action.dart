import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Consistent settings entry in app bar (Settings moved out of bottom nav).
class AppSettingsAction extends StatelessWidget {
  const AppSettingsAction({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Settings',
      icon: const Icon(Icons.settings_outlined),
      onPressed: () => context.go('/settings'),
    );
  }
}
