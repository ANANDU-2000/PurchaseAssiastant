import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/theme/theme_context_ext.dart';

class BusinessProfilePage extends ConsumerStatefulWidget {
  const BusinessProfilePage({super.key});

  @override
  ConsumerState<BusinessProfilePage> createState() => _BusinessProfilePageState();
}

class _BusinessProfilePageState extends ConsumerState<BusinessProfilePage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _gstCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _titleCtrl = TextEditingController();
    _gstCtrl = TextEditingController();
    _addressCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFromSession());
  }

  void _loadFromSession() {
    final pb = ref.read(sessionProvider)?.primaryBusiness;
    if (pb == null || !mounted) return;
    setState(() {
      _nameCtrl.text = pb.name;
      _titleCtrl.text = pb.brandingTitle ?? '';
      _gstCtrl.text = pb.gstNumber ?? '';
      _addressCtrl.text = pb.address ?? '';
      _phoneCtrl.text = pb.phone ?? '';
      _emailCtrl.text = pb.contactEmail ?? '';
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _titleCtrl.dispose();
    _gstCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  String? _validateGst(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    if (t.length != 15) return 'GSTIN must be 15 characters';
    if (!RegExp(r'^[0-9A-Z]{15}$').hasMatch(t.toUpperCase())) {
      return 'Use letters A–Z and digits only';
    }
    return null;
  }

  String? _validatePhone(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final digits = t.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return 'Enter at least 10 digits';
    return null;
  }

  Future<void> _save() async {
    final session = ref.read(sessionProvider);
    if (session == null || session.primaryBusiness.role != 'owner') return;

    final gstErr = _validateGst(_gstCtrl.text);
    final phErr = _validatePhone(_phoneCtrl.text);
    if (gstErr != null || phErr != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(gstErr ?? phErr ?? 'Invalid')),
      );
      return;
    }

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(hexaApiProvider).patchBusinessBranding(
            businessId: session.primaryBusiness.id,
            brandingTitle: _titleCtrl.text.trim(),
            gstNumber: _gstCtrl.text.trim().toUpperCase(),
            address: _addressCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            includeContactEmail: true,
            contactEmail: _emailCtrl.text,
          );
      await ref.read(sessionProvider.notifier).refreshBusinesses();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Business profile saved')));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider);
    final isOwner = session?.primaryBusiness.role == 'owner';

    return Scaffold(
      backgroundColor: context.adaptiveScaffold,
      appBar: AppBar(
        backgroundColor: context.adaptiveAppBarBg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Business profile',
          style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            'Shown on purchase invoice PDFs (GSTIN, address, phone, contact email).',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 16),
          Card(
            color: context.adaptiveCard,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Registered business name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _titleCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Invoice header title',
                      hintText: 'e.g. HARISREE AGENCY',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _gstCtrl,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 15,
                    decoration: const InputDecoration(
                      labelText: 'GSTIN (optional)',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Contact email (optional)',
                      hintText: 'For invoice PDF header',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _addressCtrl,
                    minLines: 3,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Address (optional)',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!isOwner)
                    Text(
                      'Only workspace owners can edit this profile.',
                      style: tt.bodySmall?.copyWith(color: HexaColors.loss),
                    )
                  else
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
