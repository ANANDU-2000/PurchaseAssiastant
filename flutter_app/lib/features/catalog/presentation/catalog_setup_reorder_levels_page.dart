import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';

/// Bulk set reorder thresholds for items that have none.
class CatalogSetupReorderLevelsPage extends ConsumerStatefulWidget {
  const CatalogSetupReorderLevelsPage({super.key});

  @override
  ConsumerState<CatalogSetupReorderLevelsPage> createState() =>
      _CatalogSetupReorderLevelsPageState();
}

class _CatalogSetupReorderLevelsPageState
    extends ConsumerState<CatalogSetupReorderLevelsPage> {
  final _values = <String, TextEditingController>{};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _values.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> _needsSetup(List<Map<String, dynamic>> items) {
    return [
      for (final it in items)
        if (((it['reorder_level'] as num?)?.toDouble() ?? 0) <= 0) it,
    ];
  }

  Future<void> _saveAll(List<Map<String, dynamic>> rows) async {
    final session = ref.read(sessionProvider);
    if (session == null || _saving) return;
    final bid = session.primaryBusiness.id;
    final api = ref.read(hexaApiProvider);
    final patches = <Future<void>>[];
    for (final it in rows) {
      final id = it['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final ctrl = _values[id];
      if (ctrl == null) continue;
      final v = double.tryParse(ctrl.text.trim());
      if (v == null || v <= 0) continue;
      patches.add(
        api
            .updateCatalogItem(
              businessId: bid,
              itemId: id,
              patchReorderLevel: true,
              reorderLevel: v,
            )
            .then((_) {}),
      );
    }
    if (patches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one threshold above 0')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await Future.wait(patches);
      ref.invalidate(bulkStockListProvider);
      ref.invalidate(stockListProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${patches.length} reorder level(s)')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(bulkStockListProvider);

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: const Text('Set reorder levels'),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
      ),
      body: listAsync.when(
        loading: () => const ListSkeleton(rowCount: 12, rowHeight: 64),
        error: (_, __) => FriendlyLoadError(
          message: 'Could not load catalog items',
          onRetry: () => ref.invalidate(bulkStockListProvider),
        ),
        data: (data) {
          final raw = (data['items'] as List?) ?? const [];
          final items = [
            for (final e in raw)
              if (e is Map) Map<String, dynamic>.from(e),
          ];
          final rows = _needsSetup(items);
          for (final it in rows) {
            final id = it['id']?.toString() ?? '';
            if (id.isEmpty || _values.containsKey(id)) continue;
            _values[id] = TextEditingController();
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  '${rows.length} items have no reorder threshold',
                  style: HexaDsType.body(14, color: HexaDsColors.textMuted),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  itemCount: rows.length,
                  itemBuilder: (ctx, i) {
                    final it = rows[i];
                    final id = it['id']?.toString() ?? '';
                    final name = it['name']?.toString() ?? '';
                    final unit =
                        (it['default_unit'] ?? it['unit'])?.toString() ?? 'bag';
                    final ctrl = _values[id] ?? TextEditingController();
                    return ListTile(
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(it['category_name']?.toString() ?? ''),
                      trailing: SizedBox(
                        width: 96,
                        child: TextField(
                          controller: ctrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[\d.]'),
                            ),
                          ],
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '0',
                            suffixText: unit.toUpperCase(),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: _saving ? null : () => _saveAll(rows),
                    child: _saving
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save all'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
