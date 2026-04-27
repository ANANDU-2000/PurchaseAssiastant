import 'purchase_item_entry_sheet.dart';

/// Full-screen add / edit purchase line (ENTRY Prompt 1). Same behavior as
/// [PurchaseItemEntrySheet] with [PurchaseItemEntrySheet.fullPage] enabled.
class AddItemEntryPage extends PurchaseItemEntrySheet {
  const AddItemEntryPage({
    super.key,
    required super.catalog,
    super.initial,
    required super.isEdit,
    required super.onCommitted,
    super.resolveCatalogItem,
  }) : super(fullPage: true);
}
