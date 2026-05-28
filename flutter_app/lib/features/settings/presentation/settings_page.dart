import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/config/app_config.dart';
import '../../../core/models/session.dart';
import '../../../core/notifications/local_notifications_service.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/prefs_provider.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/router/post_auth_route.dart' show sessionCanManageUsers;
import '../../../core/theme/hexa_colors.dart';
import '../../../core/theme/theme_context_ext.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _brandingTitleCtrl;
  Uint8List? _pendingLogoBytes;
  String _pendingLogoFilename = 'logo.jpg';
  bool _brandingSaving = false;
  int _superAdminGestureCount = 0;
  DateTime? _superAdminGestureAnchor;

  @override
  void initState() {
    super.initState();
    _brandingTitleCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pb = ref.read(sessionProvider)?.primaryBusiness;
      if (pb != null && mounted) {
        setState(() => _brandingTitleCtrl.text = pb.brandingTitle ?? '');
      }
    });
  }

  @override
  void dispose() {
    _brandingTitleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
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
    if (session == null || _brandingSaving) return;
    setState(() => _brandingSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      String? uploadedUrl;
      if (_pendingLogoBytes != null) {
        final logo = await ref.read(hexaApiProvider).uploadBusinessLogoBytes(
              businessId: session.primaryBusiness.id,
              bytes: _pendingLogoBytes!,
              filename: _pendingLogoFilename,
            );
        uploadedUrl = logo['branding_logo_url']?.toString() ??
            logo['logo_url']?.toString() ??
            logo['url']?.toString();
      }
      await ref.read(hexaApiProvider).patchBusinessBranding(
            businessId: session.primaryBusiness.id,
            brandingTitle: _brandingTitleCtrl.text.trim(),
            brandingLogoUrl: uploadedUrl,
          );
      await ref.read(sessionProvider.notifier).refreshBusinesses();
      if (!mounted) return;
      setState(() => _pendingLogoBytes = null);
      messenger.showSnackBar(
        const SnackBar(content: Text('Workspace branding saved')),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _brandingSaving = false);
    }
  }

  void _handleVersionLongPress(Session? session) {
    if (session?.isSuperAdmin != true) return;
    final now = DateTime.now();
    final anchor = _superAdminGestureAnchor;
    if (anchor == null || now.difference(anchor) > const Duration(seconds: 4)) {
      _superAdminGestureCount = 0;
    }
    _superAdminGestureAnchor = now;
    setState(() => _superAdminGestureCount++);
    if (_superAdminGestureCount >= 3) {
      _superAdminGestureCount = 0;
      _superAdminGestureAnchor = null;
      context.push('/admin');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final pb = session?.primaryBusiness;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final role = pb?.role.toLowerCase();
    final isOwner = role == 'owner' || session?.isSuperAdmin == true;
    final canManageUsers = session != null && sessionCanManageUsers(session);
    final notifOptIn = ref.watch(localNotificationsOptInProvider);

    return Scaffold(
      backgroundColor: context.adaptiveScaffold,
      appBar: AppBar(
        backgroundColor: context.adaptiveAppBarBg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Settings',
          style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/home'),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _SectionTitle('Account'),
          _SettingsCard(
            children: [
              ListTile(
                leading: Icon(Icons.person_outline_rounded, color: cs.primary),
                title: const Text('Session'),
                subtitle: Text(
                  session != null
                      ? 'Signed in · ${pb?.name ?? ''}'
                      : 'Not signed in',
                ),
              ),
            ],
          ),
          _SectionTitle('Quick Actions'),
          _SettingsCard(
            children: [
              _NavTile(
                icon: Icons.document_scanner_outlined,
                title: 'Scan purchase bill',
                onTap: () => context.pushNamed('purchase_scan'),
              ),
              _NavTile(
                icon: Icons.add_shopping_cart_outlined,
                title: 'New purchase',
                onTap: () => context.go('/purchase/new'),
              ),
              _NavTile(
                icon: Icons.history_rounded,
                title: 'Purchase history',
                onTap: () => context.go('/purchase'),
              ),
            ],
          ),
          _SectionTitle('Notifications'),
          _SettingsCard(
            children: [
              SwitchListTile(
                secondary: Icon(Icons.notifications_active_outlined,
                    color: cs.primary),
                title: const Text('Local notifications'),
                subtitle: const Text(
                    'Warehouse reminders and follow-ups on this device'),
                value: notifOptIn,
                onChanged: (v) => unawaited(_setNotificationsOptIn(v)),
              ),
            ],
          ),
          _SectionTitle('Business'),
          _BusinessCard(
            session: session,
            isOwner: isOwner,
            canManageUsers: canManageUsers,
            brandingTitleCtrl: _brandingTitleCtrl,
            pendingLogoBytes: _pendingLogoBytes,
            pendingLogoFilename: _pendingLogoFilename,
            brandingSaving: _brandingSaving,
            onPickLogo: _pickLogo,
            onDiscardLogo: () => setState(() => _pendingLogoBytes = null),
            onSaveBranding: _saveBranding,
          ),
          _SectionTitle('Operations'),
          _SettingsCard(
            children: [
              _NavTile(
                icon: Icons.playlist_add_check_rounded,
                title: 'Reorder list',
                subtitle: 'Items flagged for reorder',
                onTap: () => context.push('/stock/reorder'),
              ),
              if (isOwner)
                _NavTile(
                  icon: Icons.inventory_rounded,
                  title: 'Opening stock setup',
                  subtitle: 'Set initial stock and lock setup values',
                  onTap: () => context.push('/stock/opening-setup'),
                ),
              if (isOwner)
                _NavTile(
                  icon: Icons.receipt_long_rounded,
                  title: 'Staff cash purchases',
                  subtitle: 'Quick buys logged by floor staff',
                  onTap: () => context.push('/stock/staff-purchases'),
                ),
              _NavTile(
                icon: Icons.print_outlined,
                title: 'Print barcodes (bulk)',
                onTap: () => context.push('/barcode/bulk-print'),
              ),
              _NavTile(
                icon: Icons.qr_code_scanner_rounded,
                title: 'Scan item',
                onTap: () => context.push('/barcode/scan'),
              ),
            ],
          ),
          _SectionTitle('Data'),
          _SettingsCard(
            children: [
              _NavTile(
                icon: Icons.help_outline_rounded,
                title: 'Help & guide',
                subtitle: 'Daily stock, offline mode, backup steps',
                onTap: () => context.push('/settings/help'),
              ),
              _NavTile(
                icon: Icons.groups_outlined,
                title: 'Suppliers & brokers',
                subtitle: 'Contacts hub, categories, items, people',
                onTap: () => context.go('/contacts'),
              ),
              _NavTile(
                icon: Icons.inventory_2_outlined,
                title: 'Item catalog',
                subtitle: 'Categories and items for faster entry lines',
                onTap: () => context.push('/catalog'),
              ),
              _NavTile(
                icon: Icons.tune_rounded,
                title: 'Set reorder levels',
                subtitle: 'Thresholds for low-stock alerts',
                onTap: () => context.push('/catalog/setup-reorder-levels'),
              ),
              _NavTile(
                icon: Icons.qr_code_2_outlined,
                title: 'Missing item codes',
                subtitle: 'Assign codes and print barcodes',
                onTap: () => context.push('/catalog/missing-codes'),
              ),
              _NavTile(
                icon: Icons.folder_zip_outlined,
                title: 'Backup',
                subtitle: 'Download purchase records for your files',
                onTap: () => context.push('/settings/backup'),
              ),
              _NavTile(
                icon: Icons.checklist_rtl_outlined,
                title: 'Owner tasks',
                subtitle: 'Checklist progress and staff completion',
                onTap: () => context.push('/operations/owner-tasks'),
              ),
            ],
          ),
          if (session?.isSuperAdmin == true) ...[
            _SectionTitle('Admin'),
            _SettingsCard(
              children: [
                _NavTile(
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'Super admin',
                  onTap: () => context.push('/admin'),
                ),
              ],
            ),
          ],
          _SectionTitle('Troubleshooting'),
          _SettingsCard(
            children: [
              ListTile(
                leading: Icon(Icons.sync_rounded, color: cs.primary),
                title: const Text('Refresh all stats'),
                subtitle: const Text(
                  'Reloads home, reports, contacts KPIs, and purchases from the server.',
                ),
                onTap: () {
                  invalidateBusinessAggregates(ref);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Refreshing numbers...')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 28),
          Center(
            child: GestureDetector(
              onLongPress: () => _handleVersionLongPress(session),
              child: Text(
                'Version ${AppConfig.packageVersion}',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(height: 16),
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

  Future<void> _setNotificationsOptIn(bool enabled) async {
    await ref.read(localNotificationsOptInProvider.notifier).setValue(enabled);
    await LocalNotificationsService.instance.setOptIn(enabled);
  }
}

class _BusinessCard extends StatelessWidget {
  const _BusinessCard({
    required this.session,
    required this.isOwner,
    required this.canManageUsers,
    required this.brandingTitleCtrl,
    required this.pendingLogoBytes,
    required this.pendingLogoFilename,
    required this.brandingSaving,
    required this.onPickLogo,
    required this.onDiscardLogo,
    required this.onSaveBranding,
  });

  final Session? session;
  final bool isOwner;
  final bool canManageUsers;
  final TextEditingController brandingTitleCtrl;
  final Uint8List? pendingLogoBytes;
  final String pendingLogoFilename;
  final bool brandingSaving;
  final VoidCallback onPickLogo;
  final VoidCallback onDiscardLogo;
  final VoidCallback onSaveBranding;

  @override
  Widget build(BuildContext context) {
    final pb = session?.primaryBusiness;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return _SettingsCard(
      children: [
        Padding(
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
                      pb?.name ?? 'No business selected',
                      style:
                          tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              if (session != null)
                Text(
                  'Role: ${pb!.role} · Shown in app: ${pb.effectiveDisplayTitle}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              if (isOwner && pb != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Workspace branding',
                  style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: brandingTitleCtrl,
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
                      pendingBytes: pendingLogoBytes,
                      networkUrl: pb.brandingLogoUrl,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OutlinedButton.icon(
                            onPressed: brandingSaving ? null : onPickLogo,
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('Choose logo'),
                          ),
                          if (pendingLogoBytes != null)
                            Text(
                              pendingLogoFilename,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: brandingSaving ? null : onSaveBranding,
                            child: brandingSaving
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Text('Save branding'),
                          ),
                          if (pendingLogoBytes != null)
                            TextButton(
                              onPressed: brandingSaving ? null : onDiscardLogo,
                              child: const Text('Discard image'),
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
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        _NavTile(
          icon: Icons.receipt_long_outlined,
          title: 'Purchase order / business profile',
          subtitle: 'GSTIN, address, phone for PDF purchase orders',
          onTap: () => context.push('/settings/business'),
        ),
        if (canManageUsers)
          _NavTile(
            icon: Icons.group_outlined,
            title: 'Users & roles',
            subtitle: 'Staff and manager logins for this workspace',
            onTap: () => context.push('/settings/users'),
          ),
      ],
    );
  }
}

class _LogoPreview extends StatelessWidget {
  const _LogoPreview({this.pendingBytes, this.networkUrl});

  final Uint8List? pendingBytes;
  final String? networkUrl;

  @override
  Widget build(BuildContext context) {
    final img = pendingBytes != null
        ? Image.memory(pendingBytes!, fit: BoxFit.cover)
        : (networkUrl != null && networkUrl!.trim().isNotEmpty
            ? Image.network(networkUrl!, fit: BoxFit.cover)
            : null);
    return Container(
      width: 72,
      height: 72,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: HexaColors.primaryLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: img ??
          const Icon(Icons.storefront_rounded, color: HexaColors.textSecondary),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: context.adaptiveCard,
      clipBehavior: Clip.antiAlias,
      child: Column(children: _withDividers(children)),
    );
  }

  List<Widget> _withDividers(List<Widget> rows) {
    final out = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) out.add(const Divider(height: 1));
      out.add(rows[i]);
    }
    return out;
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: cs.primary),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
