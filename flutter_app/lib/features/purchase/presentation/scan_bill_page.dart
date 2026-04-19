import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/theme/hexa_colors.dart';

/// Scan / paste bill → OCR preview → confirm → returns draft line maps via `context.pop`.
class ScanBillPage extends ConsumerStatefulWidget {
  const ScanBillPage({super.key});

  @override
  ConsumerState<ScanBillPage> createState() => _ScanBillPageState();
}

class _ScanBillPageState extends ConsumerState<ScanBillPage> {
  final _paste = TextEditingController();
  String? _imageB64;
  bool _busy = false;
  String? _note;
  final List<Map<String, dynamic>> _items = [];

  String _previewRateCaption(Map<String, dynamic> m) {
    final u = (m['unit']?.toString() ?? 'kg').toLowerCase();
    final r = (m['landing_cost'] as num?)?.toDouble() ?? 0;
    if (u == 'bag') {
      return '₹${r.toStringAsFixed(2)} per bag — purchase wizard uses kg/bag from your catalog for totals';
    }
    return '₹${r.toStringAsFixed(2)} per $u';
  }

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src, maxWidth: 1600, imageQuality: 85);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() {
      _imageB64 = base64Encode(bytes);
    });
  }

  Future<void> _analyze() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() {
      _busy = true;
      _note = null;
      _items.clear();
    });
    try {
      final res = await ref.read(hexaApiProvider).mediaOcrPreview(
            businessId: session.primaryBusiness.id,
            imageBase64: _imageB64 ?? '',
            pasteText: _paste.text.trim().isEmpty ? null : _paste.text.trim(),
          );
      _note = res['note']?.toString();
      final raw = res['items'];
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          _items.add({
            'item_name': m['item_name']?.toString() ?? 'Item',
            'qty': (m['qty'] as num?)?.toDouble() ?? 1,
            'unit': (m['unit']?.toString() ?? 'kg').toLowerCase(),
            'landing_cost': (m['landing_cost'] as num?)?.toDouble() ?? 0,
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Scan bill'),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Take a photo or paste invoice lines. Lines like:\n'
            '100 bag Vaan 42\n'
            'Rice 100 kg 38',
            style: TextStyle(fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_rounded),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_rounded),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _paste,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Paste invoice text (recommended)',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _analyze,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.document_scanner_rounded),
            label: Text(_busy ? 'Analysing…' : 'Analyse'),
          ),
          if (_note != null) ...[
            const SizedBox(height: 8),
            Text(_note!, style: TextStyle(fontSize: 12, color: HexaColors.neutral)),
          ],
          const SizedBox(height: 16),
          if (_items.isNotEmpty) ...[
            Text('Preview (${_items.length})', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._items.asMap().entries.map((e) {
              final i = e.key;
              final m = e.value;
              return Card(
                child: ListTile(
                  title: Text(m['item_name']?.toString() ?? ''),
                  subtitle: Text(
                    '${m['qty']} ${m['unit']} · ${_previewRateCaption(m)}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _items.removeAt(i)),
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.pop<List<Map<String, dynamic>>>(List.from(_items)),
              child: const Text('Use these lines'),
            ),
          ],
        ],
      ),
    );
  }
}
