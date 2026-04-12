import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/models/session.dart';
import '../../../core/providers/prefs_provider.dart';
import '../../../core/theme/hexa_colors.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  Map<String, dynamic>? _billing;
  String? _billingErr;
  late final TextEditingController _brandingTitleCtrl;
  Uint8List? _pendingLogoBytes;
  String _pendingLogoFilename = 'logo.jpg';
  bool _brandingSaving = false;

  @override
  void initState() {
    super.initState();
    _brandingTitleCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshBilling();
      final s = ref.read(sessionProvider);
      final pb = s?.primaryBusiness;
      if (pb != null && mounted) {
        setState(() {
          _brandingTitleCtrl.text = pb.brandingTitle ?? '';
        });
      }
    });
  }

  @override
  void dispose() {
    _brandingTitleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
    if (x == null || !mounted) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pendingLogoBytes = bytes;
      _pendingLogoFilename = x.name.trim().isNotEmpty ? x.name.trim() : 'logo.jpg';
    });
  }

  Future<void> _saveBranding() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final bid = session.primaryBusiness.id;
    if (session.primaryBusiness.role != 'owner') return;
    setState(() => _brandingSaving = true);
    final api = ref.read(hexaApiProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_pendingLogoBytes != null) {
        await api.uploadBusinessLogoBytes(
          businessId: bid,
          bytes: _pendingLogoBytes!,
          filename: _pendingLogoFilename,
        );
      }
      await api.patchBusinessBranding(
        businessId: bid,
        brandingTitle: _brandingTitleCtrl.text.trim(),
      );
      await ref.read(sessionProvider.notifier).refreshBusinesses();
      if (!mounted) return;
      final pb = ref.read(sessionProvider)?.primaryBusiness;
      if (pb != null) {
        _brandingTitleCtrl.text = pb.brandingTitle ?? '';
      }
      setState(() => _pendingLogoBytes = null);
      messenger.showSnackBar(const SnackBar(content: Text('Branding saved')));
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _brandingSaving = false);
    }
  }

  Future<void> _clearLogo() async {
    final session = ref.read(sessionProvider);
    if (session == null || session.primaryBusiness.role != 'owner') return;
    setState(() => _brandingSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(hexaApiProvider).patchBusinessBranding(
            businessId: session.primaryBusiness.id,
            brandingLogoUrl: '',
          );
      await ref.read(sessionProvider.notifier).refreshBusinesses();
      if (mounted) {
        setState(() => _pendingLogoBytes = null);
        messenger.showSnackBar(const SnackBar(content: Text('Logo removed')));
      }
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('Could not remove logo: $e')));
    } finally {
      if (mounted) setState(() => _brandingSaving = false);
    }
  }

  Future<void> _refreshBilling() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final bid = session.primaryBusiness.id;
    final api = ref.read(hexaApiProvider);
    try {
      final m = await api.billingStatus(businessId: bid);
      if (mounted) {
        setState(() {
          _billing = m;
          _billingErr = null;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _billingErr = e.message ?? 'Billing unavailable';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider);
    ref.listen<Session?>(sessionProvider, (previous, next) {
      final pb = next?.primaryBusiness;
      if (pb == null) return;
      if (previous?.primaryBusiness.id != pb.id) {
        _brandingTitleCtrl.text = pb.brandingTitle ?? '';
        if (mounted) {
          setState(() => _pendingLogoBytes = null);
        }
      }
    });
    final autofill = ref.watch(smartAutofillEnabledProvider);
    final notif = ref.watch(localNotificationsOptInProvider);
    final isOwner = session?.primaryBusiness.role == 'owner';
    final pb = session?.primaryBusiness;

    return Scaffold(
      backgroundColor: HexaColors.canvas,
      appBar: AppBar(
        backgroundColor: HexaColors.canvas,
        surfaceTintColor: Colors.transparent,
        title: Text('Settings', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: HexaColors.textPrimary)),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded, color: HexaColors.textPrimary),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Account', style: tt.titleSmall?.copyWith(color: HexaColors.textSecondary, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: HexaColors.surfaceCard,
            child: ListTile(
              leading: Icon(Icons.person_outline_rounded, color: cs.primary),
              title: const Text('Session'),
              subtitle: Text(session != null ? 'Signed in · ${session.primaryBusiness.name}' : 'Not signed in'),
            ),
          ),
          const SizedBox(height: 20),
          Text('Business', style: tt.titleSmall?.copyWith(color: HexaColors.textSecondary, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: HexaColors.surfaceCard,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.business_rounded, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pb?.name ?? '—',
                          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  if (session != null)
                    Text(
                      'Role: ${pb!.role} · Shown in app: ${pb.effectiveDisplayTitle}',
                      style: tt.bodySmall?.copyWith(color: HexaColors.textSecondary),
                    ),
                  if (isOwner && pb != null) ...[
                    const SizedBox(height: 16),
                    Text('Workspace branding', style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _brandingTitleCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'In-app title',
                        hintText: 'Leave empty to use business name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LogoPreview(
                          pendingBytes: _pendingLogoBytes,
                          networkUrl: pb.brandingLogoUrl,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _brandingSaving ? null : _pickLogo,
                                icon: const Icon(Icons.image_outlined),
                                label: const Text('Choose logo'),
                              ),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: _brandingSaving ? null : _saveBranding,
                                child: _brandingSaving
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('Save branding'),
                              ),
                              TextButton(
                                onPressed: _brandingSaving ||
                                        (_pendingLogoBytes == null && (pb.brandingLogoUrl?.trim().isEmpty ?? true))
                                    ? null
                                    : () {
                                        if (_pendingLogoBytes != null) {
                                          setState(() => _pendingLogoBytes = null);
                                        } else {
                                          _clearLogo();
                                        }
                                      },
                                child: Text(_pendingLogoBytes != null ? 'Discard image' : 'Remove logo'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ] else if (session != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Only owners can change the in-app title and logo.',
                      style: tt.bodySmall?.copyWith(color: HexaColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Preferences', style: tt.titleSmall?.copyWith(color: HexaColors.textSecondary, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: HexaColors.surfaceCard,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.auto_awesome_rounded, color: cs.primary),
                  title: const Text('Smart autofill'),
                  subtitle: const Text('Stored on this device only. Future: suggest fields from history.'),
                  value: autofill,
                  onChanged: (v) => ref.read(smartAutofillEnabledProvider.notifier).setValue(v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Icon(Icons.notifications_active_outlined, color: cs.primary),
                  title: const Text('Local notifications'),
                  subtitle: Text(
                    notif
                        ? 'Daily summary around 9:00 (Asia/Kolkata) when the OS allows alarms.'
                        : 'Enable for a gentle daily reminder to review purchases.',
                  ),
                  value: notif,
                  onChanged: (v) => ref.read(localNotificationsOptInProvider.notifier).setValue(v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Voice & AI', style: tt.titleSmall?.copyWith(color: HexaColors.textSecondary, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: HexaColors.surfaceCard,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.mic_none_rounded, color: cs.primary),
                  title: const Text('Push-to-talk only'),
                  subtitle: const Text(
                    'We do not use an always-on microphone. Tap the mic for a short session — better battery, lower cost, clearer intent. A wake phrase would need a future OS-level integration.',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.verified_user_outlined, color: cs.primary),
                  title: const Text('Confirm before save'),
                  subtitle: const Text(
                    'Purchase lines are never auto-saved from AI. Use Preview → Save in Entries.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Integrations', style: tt.titleSmall?.copyWith(color: HexaColors.textSecondary, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: HexaColors.surfaceCard,
            child: ListTile(
              leading: Icon(Icons.chat_outlined, color: cs.primary),
              title: const Text('WhatsApp'),
              subtitle: const Text(
                'WhatsApp Business is set up for your workspace by your administrator. This app does not store messaging passwords.',
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Data', style: tt.titleSmall?.copyWith(color: HexaColors.textSecondary, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: HexaColors.surfaceCard,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.groups_outlined, color: cs.primary),
                  title: const Text('Suppliers & brokers'),
                  subtitle: const Text('Contacts hub — categories, items, people.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.go('/contacts'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.inventory_2_outlined, color: cs.primary),
                  title: const Text('Item catalog'),
                  subtitle: const Text('Categories and items for faster entry lines.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/catalog'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.straighten_rounded, color: cs.primary),
                  title: const Text('Units'),
                  subtitle: const Text('Bag, kg, piece — enforced on entry lines.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Subscription', style: tt.titleSmall?.copyWith(color: HexaColors.textSecondary, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: HexaColors.surfaceCard,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.workspace_premium_outlined, color: cs.primary),
                      const SizedBox(width: 8),
                      Text('Plan & add-ons', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const Spacer(),
                      TextButton(onPressed: _refreshBilling, child: const Text('Refresh')),
                    ],
                  ),
                  if (_billingErr != null)
                    Text(_billingErr!, style: tt.bodySmall?.copyWith(color: Colors.redAccent))
                  else if (_billing == null)
                    Text('Loading…', style: tt.bodySmall?.copyWith(color: HexaColors.textSecondary))
                  else ...[
                    Text(
                      _billing!['subscription'] == null
                          ? 'No subscription row yet — defaults apply until you pay.'
                          : 'Status: ${_billing!['subscription']['status']} · WhatsApp: ${_billing!['subscription']['whatsapp_addon']} · AI: ${_billing!['subscription']['ai_addon']}',
                      style: tt.bodySmall?.copyWith(color: HexaColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Payments: ${(_billing!['razorpay_configured'] == true) ? 'ready' : 'not configured'} · plan enforcement: ${_billing!['billing_enforce']}',
                      style: tt.bodySmall?.copyWith(color: HexaColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Checkout is completed securely; your payment is confirmed before your plan updates.',
                      style: tt.bodySmall?.copyWith(color: HexaColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.tonalIcon(
            onPressed: () async {
              await ref.read(sessionProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _LogoPreview extends StatelessWidget {
  const _LogoPreview({this.pendingBytes, this.networkUrl});

  final Uint8List? pendingBytes;
  final String? networkUrl;

  @override
  Widget build(BuildContext context) {
    final w = 72.0;
    final h = 72.0;
    if (pendingBytes != null && pendingBytes!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          pendingBytes!,
          width: w,
          height: h,
          fit: BoxFit.cover,
        ),
      );
    }
    final u = networkUrl?.trim();
    if (u != null && u.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          u,
          width: w,
          height: h,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(w, h),
        ),
      );
    }
    return _placeholder(w, h);
  }

  Widget _placeholder(double w, double h) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: HexaColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: HexaColors.borderSubtle),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.storefront_outlined, color: HexaColors.textSecondary.withValues(alpha: 0.6)),
    );
  }
}
