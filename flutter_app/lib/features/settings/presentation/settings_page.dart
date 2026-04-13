import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/config/app_config.dart';
import '../../../core/models/session.dart';
import '../../../core/providers/prefs_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/theme/theme_context_ext.dart';

/// Authkey dashboard often shows a hex app id — not dialable. Block obvious mistakes.
bool _looksLikeAuthkeyAppId(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return false;
  if (t.contains('+')) return false;
  if (RegExp(r'^[\d\s\-()]+$').hasMatch(t) && RegExp(r'\d').hasMatch(t)) {
    return false;
  }
  return t.length >= 8 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(t);
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  Map<String, dynamic>? _billing;
  String? _billingErr;
  Map<String, dynamic>? _whatsappAssistant;
  late final TextEditingController _waOverrideCtrl;
  late final TextEditingController _brandingTitleCtrl;
  Uint8List? _pendingLogoBytes;
  String _pendingLogoFilename = 'logo.jpg';
  bool _brandingSaving = false;

  Razorpay? _razorpay;
  String _billingPlanCode = 'basic';
  bool _billingWa = false;
  bool _billingAi = false;
  Map<String, dynamic>? _billingQuote;
  bool _billingQuoteLoading = false;
  bool _checkoutBusy = false;

  @override
  void initState() {
    super.initState();
    _waOverrideCtrl = TextEditingController();
    _brandingTitleCtrl = TextEditingController();
    if (!kIsWeb) {
      _razorpay = Razorpay();
      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, (dynamic response) {
        if (response is PaymentSuccessResponse) {
          unawaited(_onRazorpaySuccess(response));
        }
      });
      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, (dynamic response) {
        if (!mounted) return;
        final msg = response is PaymentFailureResponse
            ? (response.message ?? 'Payment did not complete')
            : 'Payment did not complete';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshBilling();
      unawaited(_loadWhatsappAssistant());
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
    _razorpay?.clear();
    _waOverrideCtrl.dispose();
    _brandingTitleCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchBillingQuote() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() => _billingQuoteLoading = true);
    try {
      final q = await ref.read(hexaApiProvider).billingQuote(
            businessId: session.primaryBusiness.id,
            planCode: _billingPlanCode,
            whatsappAddon: _billingWa,
            aiAddon: _billingAi,
          );
      if (mounted) {
        setState(() {
          _billingQuote = q;
          _billingQuoteLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _billingQuote = null;
          _billingQuoteLoading = false;
        });
      }
    }
  }

  Future<void> _onRazorpaySuccess(PaymentSuccessResponse r) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final pid = r.paymentId;
    final oid = r.orderId;
    final sig = r.signature;
    if (pid == null || oid == null || sig == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Missing payment details — try again or contact support.')),
        );
      }
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(hexaApiProvider).billingVerify(
            businessId: session.primaryBusiness.id,
            razorpayOrderId: oid,
            razorpayPaymentId: pid,
            razorpaySignature: sig,
          );
      await _refreshBilling();
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Payment confirmed. Your plan is updated.')));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }

  Future<void> _payWithRazorpay() async {
    if (kIsWeb || _razorpay == null) return;
    final session = ref.read(sessionProvider);
    if (session == null || session.primaryBusiness.role != 'owner') return;
    setState(() => _checkoutBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final order = await ref.read(hexaApiProvider).billingCreateOrder(
            businessId: session.primaryBusiness.id,
            planCode: _billingPlanCode,
            whatsappAddon: _billingWa,
            aiAddon: _billingAi,
          );
      final key = order['key_id']?.toString();
      final oid = order['order_id']?.toString();
      final rawAmt = order['amount_paise'];
      final amount =
          rawAmt is int ? rawAmt : int.tryParse(rawAmt?.toString() ?? '') ?? 0;
      if (key == null || oid == null || amount <= 0) {
        throw StateError('Invalid order from server');
      }
      _razorpay!.open({
        'key': key,
        'amount': amount,
        'currency': order['currency']?.toString() ?? 'INR',
        'name': AppConfig.appName,
        'description': 'Workspace subscription',
        'order_id': oid,
        'prefill': <String, String>{},
      });
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _checkoutBusy = false);
    }
  }

  Future<void> _pickLogo() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
    if (x == null || !mounted) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pendingLogoBytes = bytes;
      _pendingLogoFilename =
          x.name.trim().isNotEmpty ? x.name.trim() : 'logo.jpg';
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
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
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
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _brandingSaving = false);
    }
  }

  Future<void> _loadWhatsappAssistant() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final prefs = ref.read(sharedPreferencesProvider);
    final local = prefs.getString(kWhatsappAssistantOverrideKey)?.trim() ?? '';
    _waOverrideCtrl.text = local;
    try {
      final m = await ref.read(hexaApiProvider).getWhatsappAssistantInfo();
      if (mounted) {
        setState(() {
          _whatsappAssistant = m;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _whatsappAssistant = null;
        });
      }
    }
  }

  Future<void> _saveWhatsappOverride() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final t = _waOverrideCtrl.text.trim();
    if (t.isNotEmpty && _looksLikeAuthkeyAppId(t)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Use your WhatsApp Business phone in E.164 (e.g. +15559276064). '
            'Do not paste the Authkey app id from the dashboard.',
          ),
        ),
      );
      return;
    }
    if (t.isEmpty) {
      await prefs.remove(kWhatsappAssistantOverrideKey);
    } else {
      await prefs.setString(kWhatsappAssistantOverrideKey, t);
    }
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved on this device')),
      );
    }
  }

  /// Draft in field → saved on device → API (so Copy/Open match what you typed).
  String _effectiveAssistantE164() {
    final draft = _waOverrideCtrl.text.trim();
    if (draft.isNotEmpty) return draft;
    final prefs = ref.read(sharedPreferencesProvider);
    final saved = prefs.getString(kWhatsappAssistantOverrideKey)?.trim() ?? '';
    if (saved.isNotEmpty) return saved;
    return _whatsappAssistant?['assistant_e164']?.toString().trim() ?? '';
  }

  Future<void> _refreshBilling() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final bid = session.primaryBusiness.id;
    final api = ref.read(hexaApiProvider);
    try {
      final m = await api.billingStatus(businessId: bid);
      if (mounted) {
        final sub = m['subscription'] as Map<String, dynamic>?;
        setState(() {
          _billing = m;
          _billingErr = null;
          if (sub != null) {
            var pc = sub['plan_code']?.toString().toLowerCase() ?? 'basic';
            if (!const {'basic', 'pro', 'premium'}.contains(pc)) pc = 'basic';
            _billingPlanCode = pc;
            _billingWa = sub['whatsapp_addon'] == true;
            _billingAi = sub['ai_addon'] == true;
          }
        });
        await _fetchBillingQuote();
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
    final themeMode = ref.watch(themeModeProvider);
    final isOwner = session?.primaryBusiness.role == 'owner';
    final pb = session?.primaryBusiness;
    final onSurf = cs.onSurface;

    return Scaffold(
      backgroundColor: context.adaptiveScaffold,
      appBar: AppBar(
        backgroundColor: context.adaptiveAppBarBg,
        surfaceTintColor: Colors.transparent,
        title: Text('Settings',
            style: tt.titleLarge?.copyWith(
                fontWeight: FontWeight.w800, color: onSurf)),
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(Icons.arrow_back_rounded, color: onSurf),
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
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Account',
              style: tt.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: context.adaptiveCard,
            child: ListTile(
              leading: Icon(Icons.person_outline_rounded, color: cs.primary),
              title: const Text('Session'),
              subtitle: Text(session != null
                  ? 'Signed in · ${session.primaryBusiness.name}'
                  : 'Not signed in'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: context.adaptiveCard,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.chat_rounded, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        'WhatsApp assistant',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _whatsappAssistant?['instructions']?.toString() ??
                        'Save the assistant number in your contacts. Message from the phone you use to sign in. Purchases need a preview and YES — never auto-saved from chat alone.',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  if ((_whatsappAssistant?['assistant_e164']?.toString() ?? '')
                      .trim()
                      .isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Server',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      _whatsappAssistant!['assistant_e164'].toString().trim(),
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Text(
                    'On this device',
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _waOverrideCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'WhatsApp Business number (E.164)',
                      hintText: '+15559276064',
                      helperText:
                          'Use the phone number assigned to WhatsApp — not the Authkey app id.',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (_) => unawaited(_saveWhatsappOverride()),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: () => unawaited(_saveWhatsappOverride()),
                      child: const Text('Save on this device'),
                    ),
                  ),
                  if (_effectiveAssistantE164().isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final t = _effectiveAssistantE164();
                            await Clipboard.setData(ClipboardData(text: t));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Number copied')),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text('Copy'),
                        ),
                        FilledButton.icon(
                          onPressed: () async {
                            final raw = _effectiveAssistantE164();
                            final digits =
                                raw.replaceAll(RegExp(r'\D'), '');
                            if (digits.isEmpty) return;
                            final uri = Uri.parse('https://wa.me/$digits');
                            if (!await canLaunchUrl(uri)) return;
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          },
                          icon: const Icon(Icons.chat_rounded, size: 18),
                          label: const Text('Open WhatsApp'),
                        ),
                      ],
                    ),
                  ],
                  if (_whatsappAssistant?['linked_phone_last4'] != null &&
                      _whatsappAssistant!['linked_phone_last4']
                          .toString()
                          .isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Linked account phone ends in ···${_whatsappAssistant!['linked_phone_last4']}',
                        style: tt.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Business',
              style: tt.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: context.adaptiveCard,
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
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  if (session != null)
                    Text(
                      'Role: ${pb!.role} · Shown in app: ${pb.effectiveDisplayTitle}',
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  if (isOwner && pb != null) ...[
                    const SizedBox(height: 16),
                    Text('Workspace branding',
                        style: tt.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
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
                                onPressed:
                                    _brandingSaving ? null : _saveBranding,
                                child: _brandingSaving
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Text('Save branding'),
                              ),
                              TextButton(
                                onPressed: _brandingSaving ||
                                        (_pendingLogoBytes == null &&
                                            (pb.brandingLogoUrl
                                                    ?.trim()
                                                    .isEmpty ??
                                                true))
                                    ? null
                                    : () {
                                        if (_pendingLogoBytes != null) {
                                          setState(
                                              () => _pendingLogoBytes = null);
                                        } else {
                                          _clearLogo();
                                        }
                                      },
                                child: Text(_pendingLogoBytes != null
                                    ? 'Discard image'
                                    : 'Remove logo'),
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
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Preferences',
              style: tt.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: context.adaptiveCard,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.dark_mode_outlined, color: cs.primary),
                  title: const Text('Dark mode'),
                  subtitle: const Text(
                      'Match system is not used — pick light or dark here.'),
                  value: themeMode == ThemeMode.dark,
                  onChanged: (v) => ref
                      .read(themeModeProvider.notifier)
                      .setMode(v ? ThemeMode.dark : ThemeMode.light),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary:
                      Icon(Icons.auto_awesome_rounded, color: cs.primary),
                  title: const Text('Smart autofill'),
                  subtitle: const Text(
                      'Stored on this device only. Future: suggest fields from history.'),
                  value: autofill,
                  onChanged: (v) => ref
                      .read(smartAutofillEnabledProvider.notifier)
                      .setValue(v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Icon(Icons.notifications_active_outlined,
                      color: cs.primary),
                  title: const Text('Local notifications'),
                  subtitle: Text(
                    notif
                        ? 'Daily summary around 9:00 (Asia/Kolkata) when the OS allows alarms.'
                        : 'Enable for a gentle daily reminder to review purchases.',
                  ),
                  value: notif,
                  onChanged: (v) => ref
                      .read(localNotificationsOptInProvider.notifier)
                      .setValue(v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Voice & AI',
              style: tt.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: context.adaptiveCard,
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
                  leading:
                      Icon(Icons.verified_user_outlined, color: cs.primary),
                  title: const Text('Confirm before save'),
                  subtitle: const Text(
                    'Purchase lines are never auto-saved from AI. Use Preview → Save in Entries.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Integrations',
              style: tt.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: context.adaptiveCard,
            child: ListTile(
              leading: Icon(Icons.chat_outlined, color: cs.primary),
              title: const Text('WhatsApp'),
              subtitle: const Text(
                'WhatsApp Business is set up for your workspace by your administrator. This app does not store messaging passwords.',
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Data',
              style: tt.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: context.adaptiveCard,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.groups_outlined, color: cs.primary),
                  title: const Text('Suppliers & brokers'),
                  subtitle:
                      const Text('Contacts hub — categories, items, people.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.go('/contacts'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.inventory_2_outlined, color: cs.primary),
                  title: const Text('Item catalog'),
                  subtitle: const Text(
                      'Categories and items for faster entry lines.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/catalog'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.straighten_rounded, color: cs.primary),
                  title: const Text('Units'),
                  subtitle:
                      const Text('Bag, kg, piece — enforced on entry lines.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Subscription',
              style: tt.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            color: context.adaptiveCard,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.workspace_premium_outlined, color: cs.primary),
                      const SizedBox(width: 8),
                      Text('Plan & add-ons',
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const Spacer(),
                      TextButton(
                          onPressed: _refreshBilling,
                          child: const Text('Refresh')),
                    ],
                  ),
                  if (_billingErr != null)
                    Text(_billingErr!,
                        style: tt.bodySmall?.copyWith(color: Colors.redAccent))
                  else if (_billing == null)
                    Text('Loading…',
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant))
                  else ...[
                    Text(
                      _billing!['subscription'] == null
                          ? 'No subscription row yet — defaults apply until you pay.'
                          : 'Status: ${_billing!['subscription']['status']} · WhatsApp: ${_billing!['subscription']['whatsapp_addon']} · AI: ${_billing!['subscription']['ai_addon']}',
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Payments: ${(_billing!['razorpay_configured'] == true) ? 'ready' : 'not configured'} · plan enforcement: ${_billing!['billing_enforce']}',
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Checkout is completed securely; your payment is confirmed before your plan updates.',
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    if (isOwner) ...[
                      const SizedBox(height: 16),
                      if (_billing!['razorpay_configured'] != true)
                        Text(
                          'In-app payment needs Razorpay keys on the server (environment or admin platform integration).',
                          style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant, height: 1.35),
                        )
                      else if (kIsWeb)
                        Text(
                          'Razorpay checkout runs in the Android or iOS app — not in this web build.',
                          style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant, height: 1.35),
                        )
                      else ...[
                        Text('Renew or change plan',
                            style: tt.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          key: ValueKey(_billingPlanCode),
                          initialValue: _billingPlanCode,
                          decoration: const InputDecoration(
                            labelText: 'Plan',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'basic', child: Text('Basic')),
                            DropdownMenuItem(value: 'pro', child: Text('Pro')),
                            DropdownMenuItem(
                                value: 'premium', child: Text('Premium')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _billingPlanCode = v);
                            unawaited(_fetchBillingQuote());
                          },
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('WhatsApp add-on'),
                          subtitle: const Text(
                              'Bundled with AI add-on in pricing when either is on.'),
                          value: _billingWa,
                          onChanged: (v) {
                            setState(() => _billingWa = v);
                            unawaited(_fetchBillingQuote());
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('AI add-on'),
                          value: _billingAi,
                          onChanged: (v) {
                            setState(() => _billingAi = v);
                            unawaited(_fetchBillingQuote());
                          },
                        ),
                        if (_billingQuoteLoading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: LinearProgressIndicator(),
                          )
                        else if (_billingQuote != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Text(
                              '${NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format((_billingQuote!['amount_inr'] as num?) ?? 0)} / month',
                              style: tt.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: onSurf),
                            ),
                          ),
                        FilledButton.icon(
                          onPressed: (_checkoutBusy ||
                                  _billingQuoteLoading ||
                                  _billingQuote == null)
                              ? null
                              : () => unawaited(_payWithRazorpay()),
                          icon: const Icon(Icons.payment_rounded),
                          label: Text(_checkoutBusy
                              ? 'Opening checkout…'
                              : 'Pay with Razorpay'),
                        ),
                      ],
                    ],
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
    return Builder(
      builder: (context) {
        final o = Theme.of(context).colorScheme.onSurfaceVariant;
        return Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: HexaColors.surfaceMuted,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: HexaColors.borderSubtle),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.storefront_outlined,
              color: o.withValues(alpha: 0.6)),
        );
      },
    );
  }
}
