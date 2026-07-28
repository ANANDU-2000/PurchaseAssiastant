import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/widgets/app_button.dart';
import '../../../core/design_system/widgets/app_form_layout.dart';
import '../../../core/design_system/widgets/app_text_field.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../../../shared/widgets/desktop_page_shell.dart';

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
  String? _nameError;
  String? _gstError;
  String? _phoneError;

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

    final name = _nameCtrl.text.trim();
    final gstErr = _validateGst(_gstCtrl.text);
    final phErr = _validatePhone(_phoneCtrl.text);
    final nameErr = name.isEmpty ? 'Registered business name cannot be empty' : null;

    setState(() {
      _nameError = nameErr;
      _gstError = gstErr;
      _phoneError = phErr;
    });
    if (nameErr != null || gstErr != null || phErr != null) return;

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(hexaApiProvider).patchBusinessBranding(
            businessId: session.primaryBusiness.id,
            name: name,
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

  bool get _readOnly {
    final q = GoRouterState.of(context).uri.queryParameters['readonly'];
    return q == '1' || q == 'true';
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = _readOnly;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider);
    final isOwner = session?.primaryBusiness.role == 'owner';
    final fieldsEnabled = !readOnly && isOwner;

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
          onPressed: () => context.popOrGo('/settings'),
        ),
      ),
      body: DesktopPageShell(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              'Shown on purchase order PDFs (GSTIN, address, phone, contact email).',
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
                    AppTextField(
                      controller: _nameCtrl,
                      label: 'Registered business name',
                      enabled: fieldsEnabled,
                      errorText: _nameError,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) {
                        if (_nameError != null) setState(() => _nameError = null);
                      },
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _titleCtrl,
                      label: 'Order PDF header title',
                      helper: 'e.g. HARISREE AGENCY',
                      enabled: fieldsEnabled,
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 12),
                    AppFormRow(
                      children: [
                        AppTextField(
                          controller: _gstCtrl,
                          label: 'GSTIN (optional)',
                          enabled: fieldsEnabled,
                          errorText: _gstError,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(15),
                          ],
                          onChanged: (_) {
                            if (_gstError != null) setState(() => _gstError = null);
                          },
                        ),
                        AppTextField(
                          controller: _phoneCtrl,
                          label: 'Phone (optional)',
                          enabled: fieldsEnabled,
                          errorText: _phoneError,
                          keyboardType: TextInputType.phone,
                          onChanged: (_) {
                            if (_phoneError != null) {
                              setState(() => _phoneError = null);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _emailCtrl,
                      label: 'Contact email (optional)',
                      helper: 'For purchase order PDF header',
                      enabled: fieldsEnabled,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _addressCtrl,
                      label: 'Address (optional)',
                      enabled: fieldsEnabled,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 20),
                    if (readOnly)
                      Text(
                        'View only — contact an owner to change business details.',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      )
                    else if (!isOwner)
                      Text(
                        'Only workspace owners can edit this profile.',
                        style: tt.bodySmall?.copyWith(color: HexaColors.loss),
                      )
                    else
                      AppPrimaryButton(
                        label: 'Save',
                        loading: _saving,
                        onPressed: _save,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
