import 'package:flutter/material.dart';

import '../design_system/hexa_operational_tokens.dart';

/// Primary/secondary action with loading + brief success feedback.
class OperationalAsyncButton extends StatefulWidget {
  const OperationalAsyncButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.icon,
    this.busy = false,
    this.enabled = true,
  });

  final String label;
  final Future<void> Function()? onPressed;
  final bool filled;
  final IconData? icon;
  final bool busy;
  final bool enabled;

  @override
  State<OperationalAsyncButton> createState() => _OperationalAsyncButtonState();
}

class _OperationalAsyncButtonState extends State<OperationalAsyncButton> {
  bool _localBusy = false;
  bool _flashOk = false;

  Future<void> _run() async {
    final fn = widget.onPressed;
    if (fn == null || _localBusy || widget.busy) return;
    setState(() => _localBusy = true);
    try {
      await fn();
      if (!mounted) return;
      setState(() => _flashOk = true);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (mounted) setState(() => _flashOk = false);
    } finally {
      if (mounted) setState(() => _localBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = _localBusy || widget.busy;
    final disabled = !widget.enabled || loading || widget.onPressed == null;
    final child = loading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : _flashOk
            ? const Icon(Icons.check_rounded, size: 20)
            : Text(widget.label);

    final style = ButtonStyle(
      minimumSize: WidgetStateProperty.all(
        const Size.fromHeight(HexaOp.buttonHeight),
      ),
    );

    if (widget.filled) {
      return FilledButton(
        onPressed: disabled ? null : _run,
        style: style,
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: disabled ? null : _run,
      style: style,
      child: child,
    );
  }
}
