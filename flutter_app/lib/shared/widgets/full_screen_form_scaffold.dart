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
    this.onBackPressed,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final Widget bottom;
  final List<Widget>? actions;
  /// When set, used for the leading control (e.g. intercept back for drafts).
  final VoidCallback? onBackPressed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: onBackPressed ?? () => Navigator.of(context).maybePop(),
        ),
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
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
