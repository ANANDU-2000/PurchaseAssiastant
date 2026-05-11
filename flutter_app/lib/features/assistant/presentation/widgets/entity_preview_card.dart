import 'package:flutter/material.dart';

import '../assistant_chat_theme.dart';

/// Parsed structured fields from assistant `reply` text for `entity_preview` intents.
class EntityPreviewParse {
  EntityPreviewParse({
    required this.kindLabel,
    required this.rows,
    required this.saveDisabled,
    this.missingHint,
    this.rawTypeLower = '',
  });

  final String kindLabel;
  final List<({String label, String value})> rows;
  final bool saveDisabled;
  final String? missingHint;
  /// Lowercased `Type:` line for routing (supplier, broker, item, catalog batch, …).
  final String rawTypeLower;
}

String _titleCaseKey(String k) {
  if (k.isEmpty) return k;
  return k[0].toUpperCase() + k.substring(1).replaceAll('_', ' ');
}

List<({String label, String value})> _orderedEntityRows(
  String typeLower,
  Map<String, String> map,
) {
  String v(String a, [String? b]) {
    final x = (map[a] ?? (b != null ? map[b] : null) ?? '').trim();
    return x;
  }

  if (typeLower.contains('batch') || typeLower.contains('catalog batch')) {
    final out = <({String label, String value})>[];
    final sup = v('supplier') + v('supplier_name', 'supplier hint');
    if (sup.isNotEmpty) {
      out.add((label: 'Supplier', value: sup));
    }
    for (final e in map.entries) {
      if (e.key == 'type') continue;
      if (e.key.contains('hint')) continue;
      if (RegExp(r'^\d+$').hasMatch(e.key)) continue;
      if (e.value.trim().isEmpty) continue;
      if (e.key == 'supplier' || e.key == 'supplier_name') continue;
      if (e.value.contains('— category:') || RegExp(r'^\d+\.').hasMatch(e.value)) {
        out.add((label: 'Line', value: e.value));
      }
    }
    for (final raw in map.values) {
      final line = raw.trim();
      if (RegExp(r'^\d+\.').hasMatch(line) && line.contains('category:')) {
        if (!out.any((r) => r.value == line)) {
          out.add((label: 'Item', value: line));
        }
      }
    }
    return out;
  }

  if (typeLower.contains('supplier')) {
    return [
      (label: 'Name', value: v('name', 'supplier_name')),
      (label: 'Phone', value: v('phone', 'supplier_phone')),
      (label: 'Location', value: v('location', 'place')),
      (label: 'Broker', value: v('broker', 'broker_name')),
    ].where((r) => r.value.isNotEmpty).toList();
  }
  if (typeLower.contains('broker')) {
    final rows = <({String label, String value})>[
      (label: 'Name', value: v('name', 'broker_name')),
    ];
    final ct = v('commission_type', 'commission type');
    final cv = v('commission_value', 'commission');
    if (cv.isNotEmpty) {
      rows.add((label: 'Commission', value: ct.isNotEmpty ? '$cv ($ct)' : cv));
    } else if (ct.isNotEmpty) {
      rows.add((label: 'Commission type', value: ct));
    }
    return rows.where((r) => r.value.isNotEmpty).toList();
  }
  if (typeLower.contains('item') && !typeLower.contains('category')) {
    return [
      (label: 'Name', value: v('name', 'item_name')),
      (label: 'Category', value: v('category', 'category_name')),
      (label: 'Type', value: v('type_name', 'catalog_type')),
      (label: 'Unit', value: v('default_unit', 'unit')),
      (label: 'Kg / bag', value: v('default_kg_per_bag', 'kg_per_bag')),
    ].where((r) => r.value.isNotEmpty).toList();
  }
  if (typeLower.contains('category') && typeLower.contains('type')) {
    return [
      (label: 'Category', value: v('category', 'category_name')),
      (label: 'Type name', value: v('type_name', 'name')),
    ].where((r) => r.value.isNotEmpty).toList();
  }
  if (typeLower.contains('category') && typeLower.contains('item')) {
    return [
      (label: 'Category', value: v('category', 'category_name')),
      (label: 'Item', value: v('item', 'item_name')),
    ].where((r) => r.value.isNotEmpty).toList();
  }
  if (typeLower.contains('category')) {
    return [(label: 'Name', value: v('name', 'category_name'))];
  }
  if (typeLower.contains('variant')) {
    return [
      (label: 'Variant', value: v('variant_name', 'name')),
      (label: 'Item', value: v('item', 'item_name')),
      (label: 'Kg / bag', value: v('default_kg_per_bag', 'kg_per_bag')),
    ].where((r) => r.value.isNotEmpty).toList();
  }

  final fallback = <({String label, String value})>[];
  for (final e in map.entries) {
    if (e.key == 'type') continue;
    fallback.add((label: _titleCaseKey(e.key), value: e.value));
  }
  return fallback;
}

/// Parses lines like `Type: Supplier` / `Name: Ravu` from the assistant reply.
EntityPreviewParse? parseEntityPreviewFromReply(String reply) {
  // Batch catalog preview uses numbered lines — avoid colon-split misparsing.
  // Variant preview from server uses "Variant:" / "Under item:" without "Type:".
  if (reply.contains('Variant:') && reply.contains('Under item:')) {
    String? vName;
    String? itemName;
    for (final raw in reply.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('Variant:')) {
        vName = line.substring('Variant:'.length).trim();
      } else if (line.startsWith('Under item:')) {
        itemName = line.substring('Under item:'.length).trim();
      }
    }
    final rows = <({String label, String value})>[
      if (vName != null && vName.isNotEmpty) (label: 'Variant', value: vName),
      if (itemName != null && itemName.isNotEmpty) (label: 'Item', value: itemName),
    ];
    if (rows.isEmpty) return null;
    return EntityPreviewParse(
      kindLabel: 'Variant',
      rows: rows,
      saveDisabled: false,
      rawTypeLower: 'variant',
    );
  }

  if (reply.contains('Type: Catalog batch')) {
    final rows = <({String label, String value})>[];
    for (final raw in reply.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final lo = line.toLowerCase();
      if (lo.startsWith('type:')) continue;
      if (lo.startsWith('supplier:')) {
        rows.insert(0, (label: 'Supplier', value: line.substring(9).trim()));
      } else if (RegExp(r'^\d+\.').hasMatch(line)) {
        rows.add((label: 'Item', value: line));
      }
    }
    final saveDisabled = rows.where((r) => r.label == 'Item').isEmpty;
    return EntityPreviewParse(
      kindLabel: 'Catalog batch',
      rows: rows,
      saveDisabled: saveDisabled,
      missingHint: saveDisabled ? 'No batch lines parsed — check the preview text.' : null,
      rawTypeLower: 'catalog batch',
    );
  }

  final map = <String, String>{};
  for (final raw in reply.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final i = line.indexOf(':');
    if (i <= 0) continue;
    final k = line.substring(0, i).trim().toLowerCase();
    final v = line.substring(i + 1).trim();
    if (k.isEmpty) continue;
    map[k] = v;
  }
  final typeRaw = (map['type'] ?? '').trim();
  if (typeRaw.isEmpty) return null;

  final typeLower = typeRaw.toLowerCase();
  final rows = _orderedEntityRows(typeLower, map);

  var saveDisabled = false;
  String? missing;
  if (typeLower.contains('item') &&
      !typeLower.contains('category +') &&
      !typeLower.contains('batch')) {
    final need = <String>[];
    final name = (map['name'] ?? map['item'] ?? map['item_name'] ?? '').trim();
    final cat =
        (map['category'] ?? map['category_name'] ?? '').trim();
    if (name.isEmpty) need.add('name');
    if (cat.isEmpty) need.add('category');
    if (need.isNotEmpty) {
      saveDisabled = true;
      missing = 'Missing: ${need.join(', ')} — add in chat or tap Edit in app.';
    }
  }
  if (typeLower.contains('batch') && rows.isEmpty) {
    saveDisabled = true;
    missing = 'No batch lines parsed — check the preview text.';
  }

  return EntityPreviewParse(
    kindLabel: typeRaw,
    rows: rows,
    saveDisabled: saveDisabled,
    missingHint: missing,
    rawTypeLower: typeLower,
  );
}

/// Preview card for supplier / broker / category / item entity flows (not purchase lines).
class EntityPreviewCard extends StatelessWidget {
  const EntityPreviewCard({
    super.key,
    required this.parse,
    required this.onCancel,
    required this.onSave,
    this.onEditInForm,
  });

  final EntityPreviewParse parse;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final VoidCallback? onEditInForm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4, right: 48),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AssistantChatTheme.accent.withValues(alpha: 0.45),
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14075E54),
              blurRadius: 20,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.badge_outlined, size: 20, color: AssistantChatTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${parse.kindLabel} preview',
                      style: AssistantChatTheme.jakarta(
                        15,
                        w: FontWeight.w800,
                        c: AssistantChatTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final r in parse.rows) ...[
                _Row(label: r.label, value: r.value),
                const SizedBox(height: 6),
              ],
              if (parse.missingHint != null) ...[
                Text(
                  parse.missingHint!,
                  style: AssistantChatTheme.inter(12.5, w: FontWeight.w700, c: const Color(0xFFDC2626)),
                ),
                const SizedBox(height: 10),
              ],
              if (onEditInForm != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onEditInForm,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text('Edit in app', style: AssistantChatTheme.inter(13, w: FontWeight.w700)),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(color: Color(0xFFDC2626), width: 1.4),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Cancel', style: AssistantChatTheme.inter(14, w: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: parse.saveDisabled ? null : onSave,
                      style: FilledButton.styleFrom(
                        backgroundColor: AssistantChatTheme.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Save', style: AssistantChatTheme.inter(14, w: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: AssistantChatTheme.inter(12.5, w: FontWeight.w700, c: const Color(0xFF475569)),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            style: AssistantChatTheme.inter(13.5, w: FontWeight.w600, c: const Color(0xFF0F172A)),
          ),
        ),
      ],
    );
  }
}
