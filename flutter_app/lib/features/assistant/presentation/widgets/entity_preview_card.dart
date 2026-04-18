import 'package:flutter/material.dart';

import '../assistant_chat_theme.dart';

/// Parsed structured fields from assistant `reply` text for `entity_preview` intents.
class EntityPreviewParse {
  EntityPreviewParse({
    required this.kindLabel,
    required this.rows,
    required this.saveDisabled,
    this.missingHint,
  });

  final String kindLabel;
  final List<({String label, String value})> rows;
  final bool saveDisabled;
  final String? missingHint;
}

String _titleCaseKey(String k) {
  if (k.isEmpty) return k;
  return k[0].toUpperCase() + k.substring(1).replaceAll('_', ' ');
}

/// Parses lines like `Type: Supplier` / `Name: Ravu` from the assistant reply.
EntityPreviewParse? parseEntityPreviewFromReply(String reply) {
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

  final rows = <({String label, String value})>[];
  for (final e in map.entries) {
    if (e.key == 'type') continue;
    rows.add((label: _titleCaseKey(e.key), value: e.value));
  }

  var saveDisabled = false;
  String? missing;
  final t = typeRaw.toLowerCase();
  if (t.contains('item')) {
    final need = <String>[];
    if ((map['name'] ?? '').trim().isEmpty) need.add('name');
    final cat = (map['category'] ?? map['category_name'] ?? '').trim();
    if (cat.isEmpty) need.add('category');
    if (need.isNotEmpty) {
      saveDisabled = true;
      missing = 'Missing: ${need.join(', ')} — add in chat or open the form.';
    }
  }

  return EntityPreviewParse(
    kindLabel: typeRaw,
    rows: rows,
    saveDisabled: saveDisabled,
    missingHint: missing,
  );
}

/// Preview card for supplier / broker / category / item entity flows (not purchase lines).
class EntityPreviewCard extends StatelessWidget {
  const EntityPreviewCard({
    super.key,
    required this.parse,
    required this.onCancel,
    required this.onSave,
  });

  final EntityPreviewParse parse;
  final VoidCallback onCancel;
  final VoidCallback onSave;

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
