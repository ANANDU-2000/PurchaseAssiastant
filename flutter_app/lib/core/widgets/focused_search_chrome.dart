import 'package:flutter/material.dart';

/// Hides [chrome] (metrics, summaries, date strips) while the user is searching
/// so the search field and results stay visible without excess scrolling.
class CollapsibleSearchChrome extends StatelessWidget {
  const CollapsibleSearchChrome({
    super.key,
    required this.searchActive,
    required this.chrome,
    this.duration = const Duration(milliseconds: 220),
  });

  final bool searchActive;
  final Widget chrome;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: duration,
      alignment: Alignment.topCenter,
      curve: Curves.easeInOut,
      child: searchActive
          ? const SizedBox(width: double.infinity)
          : chrome,
    );
  }
}

/// Full-screen search host: minimal app bar + search field + body (typically results).
class FullscreenSearchShell extends StatelessWidget {
  const FullscreenSearchShell({
    super.key,
    required this.title,
    required this.searchField,
    required this.body,
    this.actions,
  });

  final String title;
  final Widget searchField;
  final Widget body;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: actions,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: searchField,
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
