import 'purchase_item_entry_sheet.dart';

/// Full-screen add/edit purchase line.
///
/// The actual full-page scaffold/keyboard UX is implemented in
/// `PurchaseItemEntrySheet` (`fullPage: true`). This wrapper exists so callers
/// can import a dedicated page type for navigation.
class AddItemEntryPage extends PurchaseItemEntrySheet {
  const AddItemEntryPage({
    super.key,
    required super.catalog,
    super.initial,
    required super.isEdit,
    required super.onCommitted,
    super.resolveCatalogItem,
    super.resolveLastDefaults,
    super.onDefaultsResolved,
    super.navigateCatalogQuickAddItem,
  }) : super(fullPage: true);
}
