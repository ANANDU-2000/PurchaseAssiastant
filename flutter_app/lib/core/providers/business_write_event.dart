import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Describes the last business write for scoped UI refresh (item-level vs global).
class BusinessWriteEvent {
  const BusinessWriteEvent({
    this.revision = 0,
    this.kind = 'unknown',
    this.affectedItemIds = const {},
    this.purchaseId,
  });

  final int revision;
  final String kind;
  final Set<String> affectedItemIds;
  final String? purchaseId;

  bool affectsItem(String itemId) =>
      itemId.isNotEmpty && affectedItemIds.contains(itemId);

  bool get isGlobal => affectedItemIds.isEmpty;
}

final businessWriteEventProvider =
    StateProvider<BusinessWriteEvent>((ref) => const BusinessWriteEvent());

/// Bump revision and optionally scope which catalog items changed.
void emitBusinessWriteEvent(
  dynamic ref, {
  String kind = 'aggregate',
  Set<String>? affectedItemIds,
  String? purchaseId,
}) {
  final prev = ref.read(businessWriteEventProvider);
  ref.read(businessWriteEventProvider.notifier).state = BusinessWriteEvent(
    revision: prev.revision + 1,
    kind: kind,
    affectedItemIds: affectedItemIds ?? const {},
    purchaseId: purchaseId,
  );
}
