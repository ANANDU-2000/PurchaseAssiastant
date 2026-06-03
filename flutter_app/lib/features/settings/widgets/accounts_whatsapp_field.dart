import 'package:flutter/material.dart';

import '../../../core/services/whatsapp_phone_normalize.dart';

/// Accounts staff WhatsApp with live valid/invalid suffix icon.
class AccountsWhatsappField extends StatefulWidget {
  const AccountsWhatsappField({
    super.key,
    required this.controller,
    this.readOnly = false,
    this.onValidityChanged,
  });

  final TextEditingController controller;
  final bool readOnly;
  final void Function(bool isValid)? onValidityChanged;

  @override
  State<AccountsWhatsappField> createState() => _AccountsWhatsappFieldState();
}

class _AccountsWhatsappFieldState extends State<AccountsWhatsappField> {
  bool? _valid;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _recompute(widget.controller.text);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() => _recompute(widget.controller.text);

  void _recompute(String text) {
    final t = text.trim();
    bool? next;
    if (t.isEmpty) {
      next = null;
    } else {
      next = isValidAccountsWhatsappInput(t);
    }
    if (next == _valid) return;
    setState(() => _valid = next);
    if (next != null) {
      widget.onValidityChanged?.call(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget? suffix;
    if (_valid == true) {
      suffix = Icon(Icons.check_circle, color: cs.primary);
    } else if (_valid == false) {
      suffix = Icon(Icons.error_outline, color: cs.error);
    }

    return TextField(
      controller: widget.controller,
      readOnly: widget.readOnly,
      keyboardType: TextInputType.phone,
      onChanged: (_) => _recompute(widget.controller.text),
      decoration: InputDecoration(
        labelText: 'Accounts Staff WhatsApp',
        hintText: '+91 … or +971 / +968 / +965 / +974',
        helperText: 'Used when you Save & Share a purchase to accounts',
        border: const OutlineInputBorder(),
        suffixIcon: suffix,
      ),
    );
  }
}
