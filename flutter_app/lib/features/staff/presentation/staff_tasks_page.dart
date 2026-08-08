import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/errors/load_state_error.dart';
import '../../../core/widgets/friendly_load_error.dart';

/// Staff / owner view of assignment tasks (Wave 5).
class StaffTasksPage extends ConsumerStatefulWidget {
  const StaffTasksPage({super.key});

  @override
  ConsumerState<StaffTasksPage> createState() => _StaffTasksPageState();
}

class _StaffTasksPageState extends ConsumerState<StaffTasksPage> {
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
      final data = await ref.read(hexaApiProvider).listStaffTasks(businessId: bid);
      if (!mounted) return;
      setState(() {
        _items = (data['items'] as List?) ?? [];
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff tasks'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const LinearProgressIndicator(minHeight: 2)
          : _error != null
              ? FriendlyLoadError(message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? const Center(
                      child: Text(
                        'No tasks assigned.',
                        style: TextStyle(color: HexaColors.neutral),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final t = _items[i];
                        if (t is! Map) return const SizedBox.shrink();
                        return ListTile(
                          title: Text(
                            '${t['task_type'] ?? 'task'} · ${t['status'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            'staff ${t['staff_id']}'
                            '${t['reference_id'] != null ? ' · ref ${t['reference_id']}' : ''}',
                          ),
                        );
                      },
                    ),
    );
  }
}
