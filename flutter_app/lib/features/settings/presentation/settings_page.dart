import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/prefs_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider);
    final autofill = ref.watch(smartAutofillEnabledProvider);
    final notif = ref.watch(localNotificationsOptInProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text('Workspace', style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(Icons.business_rounded, color: cs.primary),
              title: Text(session?.primaryBusiness.name ?? '—'),
              subtitle: Text('Role: ${session?.primaryBusiness.role ?? "—"}'),
            ),
          ),
          const SizedBox(height: 20),
          Text('Preferences', style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Card(
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
                  title: const Text('Notifications'),
                  subtitle: const Text('Local preference only. Server push is not configured yet.'),
                  value: notif,
                  onChanged: (v) => ref.read(localNotificationsOptInProvider.notifier).setValue(v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Data', style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
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
                  subtitle: const Text('kg, box, piece — enforced on entry lines.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
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
