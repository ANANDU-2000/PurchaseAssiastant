import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/widgets/app_button.dart';
import '../../../core/design_system/widgets/app_text_field.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/snack.dart';
import '../../../core/errors/load_state_error.dart';
import '../../../core/widgets/friendly_load_error.dart';

const _credentialTypes = <String>[
  'openrouter_key',
  'gemini_key',
  'groq_key',
  'openai_key',
  'whatsapp_api_key',
  'whatsapp_staff_number',
];

/// Owner-only: write-only provider credentials (never shows plaintext).
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
  final _controllers = <String, TextEditingController>{};
  String? _saving;

  @override
  void initState() {
    super.initState();
    for (final t in _credentialTypes) {
      _controllers[t] = TextEditingController();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
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

  Future<void> _save(String type) async {
    final session = ref.read(sessionProvider);
    final bid = session?.primaryBusiness.id;
    final value = _controllers[type]?.text.trim() ?? '';
    if (bid == null || bid.isEmpty || value.isEmpty) return;
    setState(() => _saving = type);
    try {
      final res = await ref.read(hexaApiProvider).putProviderCredential(
        businessId: bid,
        credentialType: type,
        value: value,
      );
      _controllers[type]?.clear();
      if (!mounted) return;
      showTopSnack(
        context,
        'Saved · last 4 ${res['last_4_chars'] ?? '••••'}',
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      showTopSnack(context, loadStateErrorSubtitle(e));
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API credentials')),
      body: _loading
          ? const LinearProgressIndicator(minHeight: 2)
          : _error != null
              ? FriendlyLoadError(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Keys are stored encrypted. Values are never shown again — '
                      'only the last 4 characters after save.',
                      style: TextStyle(color: HexaColors.neutral, height: 1.35),
                    ),
                    const SizedBox(height: 16),
                    for (final type in _credentialTypes) ...[
                      Text(
                        type,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _byType[type] == null
                            ? 'Not configured (env fallback if set)'
                            : '•••• ${_byType[type]?['last_4_chars'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: HexaColors.neutral,
                        ),
                      ),
                      const SizedBox(height: 8),
                      AppTextField(
                        controller: _controllers[type]!,
                        label: 'New value',
                        obscureText: true,
                      ),
                      const SizedBox(height: 8),
                      AppPrimaryButton(
                        label: _saving == type ? 'Saving…' : 'Save',
                        loading: _saving == type,
                        onPressed: () => _save(type),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
    );
  }
}
