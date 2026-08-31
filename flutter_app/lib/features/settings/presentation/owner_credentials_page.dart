import 'package:flutter/material.dart';

import '../../../shared/widgets/desktop_page_shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/widgets/app_text_field.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/snack.dart';
import '../../../core/errors/load_state_error.dart';
import '../../../shared/widgets/hexa_empty_state.dart';

const _credentialTypes = <String>[
  'openrouter_key',
  'gemini_key',
  'groq_key',
  'openai_key',
  'whatsapp_api_key',
  'whatsapp_staff_number',
  'whatsapp_phone_number_id',
];

/// Owner or admin: write-only provider credentials (never shows plaintext).
class OwnerCredentialsPage extends ConsumerStatefulWidget {
  const OwnerCredentialsPage({super.key});

  @override
  ConsumerState<OwnerCredentialsPage> createState() =>
      _OwnerCredentialsPageState();
}

class _OwnerCredentialsPageState extends ConsumerState<OwnerCredentialsPage> {
  Map<String, dynamic> _byType = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = ref.read(sessionProvider);
    final bid = session?.primaryBusiness.id;
    if (bid == null || bid.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No business selected';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data =
          await ref.read(hexaApiProvider).listProviderCredentials(businessId: bid);
      final items = (data['items'] as List?) ?? [];
      final map = <String, dynamic>{};
      for (final e in items) {
        if (e is Map && e['credential_type'] != null) {
          map[e['credential_type'].toString()] = e;
        }
      }
      if (!mounted) return;
      setState(() {
        _byType = map;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = loadStateErrorSubtitle(e);
      });
    }
  }

  Future<void> _save(String type, String value) async {
    final session = ref.read(sessionProvider);
    final bid = session?.primaryBusiness.id;
    if (bid == null || bid.isEmpty || value.isEmpty) return;
    try {
      final res = await ref.read(hexaApiProvider).putProviderCredential(
        businessId: bid,
        credentialType: type,
        value: value,
      );
      if (!mounted) return;
      showTopSnack(
        context,
        'Saved · last 4 ${res['last_4_chars'] ?? '••••'}',
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      showTopSnack(context, loadStateErrorSubtitle(e));
    }
  }

  void _showEditDialog(String type) {
    final ctrl = TextEditingController();
    final isPhoneId = type == 'whatsapp_phone_number_id';
    final isStaffNum = type == 'whatsapp_staff_number';
    final isPlain = isPhoneId || isStaffNum;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_labelFor(type)),
        content: AppTextField(
          controller: ctrl,
          label: 'New value',
          obscureText: !isPlain,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final value = ctrl.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(ctx);
              await _save(type, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).then((_) => ctrl.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('API credentials')),
      body: DesktopPageShell(
        padding: EdgeInsets.zero,
        child: _loading
            ? const LinearProgressIndicator(minHeight: 2)
            : _error != null
                ? OwnerCredentialsLoadError(
                    title: _error!,
                    onRetry: _load,
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Owner and admin can update WhatsApp and AI keys. '
                      'Stored encrypted — values are never shown again, only last 4 after save. '
                      'Runtime uses DB value first, then server env.',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Table(
                        columnWidths: const {
                          0: FlexColumnWidth(2),
                          1: FlexColumnWidth(2),
                          2: FlexColumnWidth(1),
                        },
                        children: [
                          TableRow(
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                            ),
                            children: [
                              _tableHeader('Provider', cs, tt),
                              _tableHeader('Status', cs, tt),
                              _tableHeader('Action', cs, tt),
                            ],
                          ),
                          for (final type in _credentialTypes)
                            TableRow(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    _labelFor(type),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    _byType[type] == null
                                        ? 'Not configured'
                                        : '•••• ${_byType[type]?['last_4_chars'] ?? ''}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: _byType[type] == null
                                          ? cs.onSurfaceVariant
                                          : HexaColors.brandPrimary,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: IconButton(
                                      tooltip: 'Update',
                                      icon: Icon(
                                        Icons.edit_outlined,
                                        size: 20,
                                        color: cs.primary,
                                      ),
                                      onPressed: () => _showEditDialog(type),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
      ),
    );
  }

  Widget _tableHeader(String text, ColorScheme cs, TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        text,
        style: tt.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  String _labelFor(String type) {
    switch (type) {
      case 'openrouter_key':
        return 'OpenRouter API key';
      case 'gemini_key':
        return 'Gemini API key';
      case 'groq_key':
        return 'Groq API key';
      case 'openai_key':
        return 'OpenAI API key';
      case 'whatsapp_api_key':
        return 'WhatsApp Cloud API token';
      case 'whatsapp_staff_number':
        return 'Staff WhatsApp number (E.164)';
      case 'whatsapp_phone_number_id':
        return 'WhatsApp phone number ID';
      default:
        return type;
    }
  }
}

/// Owner API credentials list load failure.
@visibleForTesting
class OwnerCredentialsLoadError extends StatelessWidget {
  const OwnerCredentialsLoadError({
    super.key,
    required this.title,
    required this.onRetry,
  });

  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return HexaEmptyState(
      icon: Icons.vpn_key_outlined,
      title: title,
      subtitle: 'Check your connection, then retry.',
      primaryActionLabel: 'Retry',
      onPrimaryAction: onRetry,
    );
  }
}
