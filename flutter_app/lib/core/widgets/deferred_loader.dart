import 'package:flutter/widgets.dart';

/// A widget that lazily loads its child using Dart deferred imports.
///
/// Usage:
/// ```dart
/// DeferredLoader(
///   loader: () => import('heavy_feature.dart'),
///   builder: () => const HeavyFeatureWidget(),
/// )
/// ```
///
/// While loading, shows [placeholder] (defaults to an empty box).
class DeferredLoader extends StatefulWidget {
  const DeferredLoader({
    required this.loader,
    required this.builder,
    this.placeholder,
    super.key,
  });

  /// The deferred import to load. Typically: `() => import('path.dart')`
  final Future<void> Function() loader;

  /// Called after the deferred import completes. Returns the widget to display.
  final WidgetBuilder builder;

  /// Widget shown while the deferred import is loading.
  final WidgetBuilder? placeholder;

  @override
  State<DeferredLoader> createState() => _DeferredLoaderState();
}

class _DeferredLoaderState extends State<DeferredLoader> {
  bool _loaded = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await widget.loader();
      if (mounted) setState(() => _loaded = true);
    } catch (e) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error || !_loaded) {
      return widget.placeholder?.call(context) ??
          const SizedBox.shrink();
    }
    return widget.builder(context);
  }
}
