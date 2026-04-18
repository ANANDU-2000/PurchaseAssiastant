import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/search/catalog_fuzzy.dart';
import '../../../core/theme/hexa_colors.dart';

/// Full-screen create subcategory (category type).
class CatalogAddSubcategoryPage extends ConsumerStatefulWidget {
  const CatalogAddSubcategoryPage({super.key, required this.categoryId});

  final String categoryId;

  @override
  ConsumerState<CatalogAddSubcategoryPage> createState() =>
      _CatalogAddSubcategoryPageState();
}

class _CatalogAddSubcategoryPageState
    extends ConsumerState<CatalogAddSubcategoryPage> {
  final _name = TextEditingController();
  bool _saving = false;
  bool _touched = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final n = _name.text.trim();
    if (n.isEmpty) {
      setState(() => _touched = true);
      return;
    }
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final types = await ref.read(categoryTypesListProvider(widget.categoryId).future);
      final similar = catalogFuzzyRank(
        n,
        types,
        (t) => t['name']?.toString() ?? '',
        minScore: 86,
        limit: 4,
      );
      if (similar.isNotEmpty && mounted) {
        final sample = similar
            .map((t) => t['name']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .take(2)
            .join('", "');
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Similar subcategory exists'),
            content: Text(
              sample.isEmpty
                  ? 'A close name match exists. Create "$n" anyway?'
                  : 'Close matches include "$sample". Create "$n" anyway?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Go back')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
            ],
          ),
        );
        if (go != true) return;
      }
    } catch (_) {}
    setState(() => _saving = true);
    try {
      await ref.read(hexaApiProvider).createCategoryType(
            businessId: session.primaryBusiness.id,
            categoryId: widget.categoryId,
            name: n,
          );
      ref.invalidate(categoryTypesListProvider(widget.categoryId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subcategory created')),
        );
        context.pop(true);
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final err = _touched && _name.text.trim().isEmpty;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New subcategory'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _saving ? null : () => context.pop(false),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. Biriyani rice',
                    errorText: err ? 'Enter a name' : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: err
                            ? HexaColors.loss
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  onChanged: (_) {
                    if (_touched) setState(() {});
                  },
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => context.pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _create,
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Create'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
