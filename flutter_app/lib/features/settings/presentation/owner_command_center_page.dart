import 'package:flutter/material.dart';

import '../../../shared/widgets/desktop_page_shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/errors/load_state_error.dart';
import '../../../shared/widgets/hexa_empty_state.dart';

/// Owner command center — exception-first aggregate.
class OwnerCommandCenterPage extends ConsumerStatefulWidget {
  const OwnerCommandCenterPage({super.key});

  @override
  ConsumerState<OwnerCommandCenterPage> createState() =>
      _OwnerCommandCenterPageState();
}

class _OwnerCommandCenterPageState extends ConsumerState<OwnerCommandCenterPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  List<dynamic> _waItems = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      await _loadWa();
    });
  }

  Future<void> _load() async {
    final bid = ref.read(sessionProvider)?.primaryBusiness.id;
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
          await ref.read(hexaApiProvider).fetchOwnerDashboard(businessId: bid);
      if (!mounted) return;
      setState(() {
        _data = data;
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

  Future<void> _loadWa() async {
    final bid = ref.read(sessionProvider)?.primaryBusiness.id;
    if (bid == null || bid.isEmpty) return;
    try {
      final data =
          await ref.read(hexaApiProvider).listWhatsappDeliveries(businessId: bid);
      if (!mounted) return;
      setState(() => _waItems = (data['items'] as List?) ?? []);
    } catch (_) {
      // Soft-fail — dashboard still useful without WA log.
    }
  }

  Future<void> _resendWa(String poId) async {
    final bid = ref.read(sessionProvider)?.primaryBusiness.id;
    if (bid == null || poId.isEmpty) return;
    try {
      await ref.read(hexaApiProvider).resendWhatsappDelivery(
            businessId: bid,
            poId: poId,
          );
      await _loadWa();
      await _load();
    } catch (e) {
      if (!mounted) return;
      // Error surfaces via refresh; keep UI calm.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Owner command center'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: DesktopPageShell(
        padding: EdgeInsets.zero,
        child: _loading
            ? const LinearProgressIndicator(minHeight: 2)
            : _error != null
                ? OwnerCommandCenterLoadError(
                    title: _error!,
                    onRetry: _load,
                  )
                : OwnerCommandCenterBody(
                    data: _data ?? const {},
                    waItems: _waItems,
                    onRefreshWa: _loadWa,
                    onResendWa: _resendWa,
                  ),
      ),
    );
  }
}

/// Loaded command-center content — extracted for widget tests.
class OwnerCommandCenterBody extends StatelessWidget {
  const OwnerCommandCenterBody({
    super.key,
    required this.data,
    required this.waItems,
    required this.onRefreshWa,
    required this.onResendWa,
  });

  final Map<String, dynamic> data;
  final List<dynamic> waItems;
  final VoidCallback onRefreshWa;
  final ValueChanged<String> onResendWa;

  static final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  @override
  Widget build(BuildContext context) {
    final spend = (data['comparison'] as Map?)?['spend_last_7_days'];
    final stock = data['stock'] as Map? ?? {};
    final backup = data['backup'] as Map? ?? {};
    final exceptions = (data['exceptions'] as List?) ?? [];
    final staff = (data['staff_performance'] as List?) ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Needs attention',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        if (exceptions.isEmpty)
          HexaEmptyState(
            icon: Icons.check_circle_outline_rounded,
            title: 'No exceptions right now',
            subtitle: 'Low stock and delivery issues will show here.',
            primaryActionLabel: 'Open stock',
            onPrimaryAction: () => context.push('/stock'),
          )
        else
          for (final e in exceptions)
            if (e is Map)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.warning_amber_rounded,
                  color: HexaColors.warning,
                ),
                title: Text(e['message']?.toString() ?? '—'),
              ),
        const Divider(height: 32),
        Text(
          'Stock · low ${stock['low_count'] ?? 0} · out ${stock['out_count'] ?? 0}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Spend (7d): ${_money.format((spend is num) ? spend : 0)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Backup: ${backup['last_status'] ?? 'none'}'
          '${backup['last_at'] != null ? ' · ${backup['last_at']}' : ''}',
          style: const TextStyle(color: HexaColors.neutral),
        ),
        const SizedBox(height: 8),
        Text(
          'Damage pending: ${(data['damage'] as Map?)?['pending_count'] ?? 0}'
          ' · AI today: ${(data['ai_usage'] as Map?)?['requests_today'] ?? 0}'
          ' · WhatsApp queue: ${(data['whatsapp'] as Map?)?['needs_attention'] ?? 0}',
          style: const TextStyle(color: HexaColors.neutral),
        ),
        const Divider(height: 32),
        const Text(
          'WhatsApp PO deliveries',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onRefreshWa,
          child: const Text('Refresh delivery log'),
        ),
        if (waItems.isEmpty)
          const HexaEmptyState(
            icon: Icons.chat_outlined,
            title: 'No delivery attempts yet',
            subtitle: 'WhatsApp PO send attempts will list here.',
          )
        else
          for (final w in waItems.take(12))
            if (w is Map)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${w['status']} · PO ${w['po_id']}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(w['error_message']?.toString() ?? ''),
                trailing: (w['status'] == 'failed' ||
                        w['status'] == 'pending_manual')
                    ? TextButton(
                        onPressed: () => onResendWa('${w['po_id']}'),
                        child: const Text('Resend'),
                      )
                    : null,
              ),
        const Divider(height: 32),
        const Text(
          'Staff tasks',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        if (staff.isEmpty)
          HexaEmptyState(
            icon: Icons.assignment_outlined,
            title: 'No staff tasks yet',
            subtitle: 'Assigned warehouse tasks will summarize here.',
            primaryActionLabel: 'Open tasks board',
            onPrimaryAction: () => context.push('/staff/tasks-board'),
          )
        else
          for (final s in staff)
            if (s is Map)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Staff ${s['staff_id']}'),
                subtitle: Text(
                  'done ${s['completed']} · pending ${s['pending']} · '
                  'rejected ${s['rejected']}',
                ),
              ),
      ],
    );
  }
}

/// Owner command center dashboard load failure.
@visibleForTesting
class OwnerCommandCenterLoadError extends StatelessWidget {
  const OwnerCommandCenterLoadError({
    super.key,
    required this.title,
    required this.onRetry,
  });

  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return HexaEmptyState(
      icon: Icons.dashboard_outlined,
      title: title,
      subtitle: 'Check your connection, then retry.',
      primaryActionLabel: 'Retry',
      onPrimaryAction: onRetry,
    );
  }
}
