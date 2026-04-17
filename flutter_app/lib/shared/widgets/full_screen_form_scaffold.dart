import 'package:flutter/material.dart';

/// One primary body region + fixed bottom CTA (avoids nested scroll in flows).
class FullScreenFormScaffold extends StatelessWidget {
  const FullScreenFormScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    required this.bottom,
    this.actions,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final Widget bottom;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
        actions: actions,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: body),
          Material(
            elevation: 8,
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(top: false, child: bottom),
          ),
        ],
      ),
    );
  }
}
