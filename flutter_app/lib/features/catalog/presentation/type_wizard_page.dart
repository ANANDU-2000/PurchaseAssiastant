import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../shared/widgets/full_screen_form_scaffold.dart';

class TypeWizardPage extends ConsumerStatefulWidget {
  const TypeWizardPage({super.key, required this.categoryId});

  final String categoryId;

  @override
  ConsumerState<TypeWizardPage> createState() => _TypeWizardPageState();
}

class _TypeWizardPageState extends ConsumerState<TypeWizardPage> {
  final _name = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    _err = null;
    if (_name.text.trim().isEmpty) {
      setState(() => _err = 'Type name is required');
      return;
    }
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).createCategoryType(
            businessId: session.primaryBusiness.id,
            categoryId: widget.categoryId,
            name: _name.text.trim(),
          );
      if (!mounted) return;
      context.pop(true);
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FullScreenFormScaffold(
      title: 'New subcategory',
      subtitle: 'Create type for this category',
      onBackPressed: () => context.pop(false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Name *',
              hintText: 'e.g. Biriyani rice',
              errorText: _err,
              isDense: true,
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onChanged: (_) {
              if (_err != null) setState(() => _err = null);
            },
          ),
        ],
      ),
      bottom: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
            const Spacer(),
            FilledButton(onPressed: _save, child: const Text('Create')),
          ],
        ),
      ),
    );
  }
}
