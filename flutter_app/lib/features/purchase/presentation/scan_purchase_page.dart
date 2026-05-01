
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/theme/hexa_colors.dart';
import '../domain/purchase_draft.dart';

class ScanPurchasePage extends ConsumerStatefulWidget {
  const ScanPurchasePage({super.key});

  @override
  ConsumerState<ScanPurchasePage> createState() => _ScanPurchasePageState();
}

class _ScanPurchasePageState extends ConsumerState<ScanPurchasePage> {
  bool _busy = false;
  String? _note;

  /// Server keys for red borders after scan.
  final Set<String> _missing = {};
  List<_RowEdit> _rows = [];
  List<int>? _jpegBytes;

  final _supplierCtrl = TextEditingController();

  Future<void> _pick(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src);
    if (x == null) return;
    final raw = await x.readAsBytes();
    for (final old in _rows) {
      old.dispose();
    }
    setState(() {
      _jpegBytes = null;
      _rows = [];
      _missing.clear();
      _note = null;
    });
    try {
      final compressed = await _compressForUpload(raw);
      setState(() => _jpegBytes = compressed);
    } catch (_) {
      setState(() => _jpegBytes = raw);
    }
  }

  Future<List<int>> _compressForUpload(List<int> raw) async {
    final decoded = img.decodeImage(Uint8List.fromList(raw));
    if (decoded == null) return Uint8List.fromList(raw);
    const maxW = 1600;
    final resized =
        decoded.width > maxW ? img.copyResize(decoded, width: maxW) : decoded;
    return List<int>.from(img.encodeJpg(resized, quality: 82));
  }

  Future<void> _scan() async {
    final session = ref.read(sessionProvider);
    if (session == null || _jpegBytes == null || _jpegBytes!.isEmpty) return;
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      final res = await ref.read(hexaApiProvider).scanPurchaseBillMultipart(
            businessId: session.primaryBusiness.id,
            imageBytes: _jpegBytes!,
            filename: 'bill_scan.jpg',
          );
      final miss = res['missing_fields'];
      final nextMiss = <String>{};
      if (miss is List) {
        for (final e in miss) {
          nextMiss.add(e.toString());
        }
      }
      final supplier = res['supplier_name']?.toString().trim();
      _supplierCtrl.text = supplier ?? '';
      final items = res['items'];
      final nextRows = <_RowEdit>[];
      if (items is List) {
        for (final e in items) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          nextRows.add(
            _RowEdit(
              name: TextEditingController(text: m['name']?.toString() ?? ''),
              qty: TextEditingController(
                text: _fmtQty((m['qty'] as num?)?.toDouble() ?? 1),
              ),
              unit:
                  TextEditingController(text: m['unit']?.toString() ?? 'kg'),
              rate: TextEditingController(
                text: ((m['rate'] as num?)?.toDouble() ?? 0)
                    .toStringAsFixed(2),
              ),
            ),
          );
        }
      }
      if (!mounted) return;
      for (final old in _rows) {
        old.dispose();
      }
      setState(() {
        _missing.clear();
        _missing.addAll(nextMiss);
        _rows = nextRows.isEmpty ? [_RowEdit.empty()] : nextRows;
        _note = res['note']?.toString();
      });
      HapticFeedback.selectionClick();
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(e))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scan failed')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  PurchaseDraft _buildDraftFromUi() {
    final lines = <PurchaseLineDraft>[];
    for (final r in _rows) {
      final name = r.name.text.trim();
      final qty = double.tryParse(r.qty.text.trim()) ?? 0;
      final unit = r.unit.text.trim().toLowerCase();
      final rate = double.tryParse(r.rate.text.trim()) ?? 0;
      if (name.isEmpty && qty <= 0 && rate <= 0) continue;
      lines.add(
        PurchaseLineDraft(
          catalogItemId: null,
          itemName: name.isEmpty ? 'Item' : name,
          qty: qty > 0 ? qty : 1,
          unit: unit.isEmpty ? 'kg' : unit,
          landingCost: rate > 0 ? rate : 0.01,
        ),
      );
    }
    return PurchaseDraft(
      purchaseDate: DateTime.now(),
      supplierId: null,
      supplierName: _supplierCtrl.text.trim().isEmpty
          ? null
          : _supplierCtrl.text.trim(),
      invoiceNumber: null,
      lines: lines,
    );
  }

  bool _missingSupplier() =>
      _supplierCtrl.text.trim().isEmpty &&
      (_missing.contains('supplier_name') || _rows.isNotEmpty);

  Widget _supplierField(bool highlight) {
    return TextField(
      controller: _supplierCtrl,
      decoration: InputDecoration(
        labelText: 'Supplier (from bill)',
        border: OutlineInputBorder(
          borderSide: BorderSide(
            color: highlight ? Colors.red : Colors.grey,
            width: highlight ? 1.5 : 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: highlight ? Colors.red : Colors.grey[300]!,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: highlight ? Colors.red : HexaColors.brandPrimary,
            width: 1.5,
          ),
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _supplierCtrl.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  String _fmtQty(double q) =>
      q == q.roundToDouble() ? q.round().toString() : q.toString();

  void _removeRow(int i) {
    setState(() {
      _rows[i].dispose();
      final copy = List<_RowEdit>.from(_rows)..removeAt(i);
      _rows = copy.isEmpty ? [_RowEdit.empty()] : copy;
    });
  }

  bool _warnLineCell(int idx, String key) =>
      _missing.contains('line_$idx.$key');

  InputDecoration _lineDeco(String label, {required bool warn}) =>
      InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(
          borderSide: BorderSide(
            color: warn ? Colors.red : Colors.grey,
            width: warn ? 1.35 : 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: warn ? Colors.red : Colors.grey[300]!,
            width: warn ? 1.35 : 1,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan purchase bill'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Take or choose a bill photo — we extract a draft only. Confirm every field; '
            'then open the purchase wizard and link catalog items before saving.',
            style: TextStyle(height: 1.35, fontSize: 13),
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
          if (_jpegBytes != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _scan,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.document_scanner_rounded),
              label: Text(_busy ? 'Scanning…' : 'Extract text'),
            ),
          ],
          if (_note != null && _note!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_note!, style: TextStyle(fontSize: 12, color: Colors.grey[800])),
          ],
          const SizedBox(height: 16),
          Text('Review',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _supplierField(_missingSupplier()),
          const SizedBox(height: 12),
          if (_rows.isEmpty)
            const Text(
              'No lines yet — scan or add rows manually.',
              style: TextStyle(fontSize: 12),
            )
          else
            ..._rows.asMap().entries.map((e) {
              final i = e.key;
              final r = e.value;
              final rowWarn =
                  _missing.any((m) => m.startsWith('line_$i.'));
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: rowWarn
                        ? Colors.red.withValues(alpha: 0.65)
                        : Colors.grey.shade300,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text('Line ${i + 1}',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => _removeRow(i),
                          ),
                        ],
                      ),
                      TextField(
                        controller: r.name,
                        decoration: _lineDeco('Item name',
                            warn: _warnLineCell(i, 'item_name')),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: r.qty,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration:
                                  _lineDeco('Qty', warn: _warnLineCell(i, 'qty')),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: r.unit,
                              decoration: _lineDeco('Unit',
                                  warn: _warnLineCell(i, 'unit')),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 4,
                            child: TextField(
                              controller: r.rate,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration: _lineDeco('Rate ₹',
                                  warn: _warnLineCell(i, 'rate')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              setState(() => _rows = [..._rows, _RowEdit.empty()]);
            },
            icon: const Icon(Icons.add),
            label: const Text('Add blank line'),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: (_rows.any((r) => r.name.text.trim().isNotEmpty) ||
                    _supplierCtrl.text.trim().isNotEmpty)
                ? () {
                    final d = _buildDraftFromUi();
                    context.push('/purchase/new', extra: d);
                  }
                : null,
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('Use this data → New purchase'),
          ),
        ],
      ),
    );
  }
}

class _RowEdit {
  _RowEdit({
    required this.name,
    required this.qty,
    required this.unit,
    required this.rate,
  });

  factory _RowEdit.empty() {
    return _RowEdit(
      name: TextEditingController(),
      qty: TextEditingController(text: '1'),
      unit: TextEditingController(text: 'kg'),
      rate: TextEditingController(),
    );
  }

  final TextEditingController name;
  final TextEditingController qty;
  final TextEditingController unit;
  final TextEditingController rate;

  void dispose() {
    name.dispose();
    qty.dispose();
    unit.dispose();
    rate.dispose();
  }
}
