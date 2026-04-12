import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    await ref.read(sessionProvider.notifier).restore();
    if (!mounted) return;
    final s = ref.read(sessionProvider);
    if (s != null) {
      context.go('/home');
      return;
    }
    ({String? access, String? refresh}) t;
    try {
      t = await ref.read(tokenStoreProvider).read();
    } catch (_) {
      if (mounted) context.go('/login');
      return;
    }
    if (t.access != null && t.refresh != null) {
      setState(() {
        _busy = false;
        _error = 'Could not reach the server. Your login is still saved — tap Retry or check the connection.';
      });
      return;
    }
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hub_rounded, size: 56, color: cs.primary),
              const SizedBox(height: 20),
              Text(
                'HEXA',
                style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 2),
              ),
              const SizedBox(height: 12),
              if (_busy) const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
              if (_error != null) ...[
                const SizedBox(height: 20),
                Text(_error!, textAlign: TextAlign.center, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _boot,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Use another account'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
