import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/catalog_providers.dart';
import '../../core/providers/contacts_hub_provider.dart';

/// Bust all category / subcategory pickers after a taxonomy write.
void invalidateCatalogTaxonomy(WidgetRef ref, {String? categoryId}) {
  ref.invalidate(itemCategoriesListProvider);
  ref.invalidate(categoryTypesIndexProvider);
  ref.invalidate(catalogItemsListProvider);
  ref.invalidate(contactsCategoriesProvider);
  if (categoryId != null && categoryId.isNotEmpty) {
    ref.invalidate(categoryTypesListProvider(categoryId));
  }
}

/// Result of creating category and optional subcategory (type).
class CatalogTaxonomyCreateResult {
  const CatalogTaxonomyCreateResult({
    required this.categoryId,
    required this.categoryName,
    this.typeId,
    this.typeName,
  });

  final String categoryId;
  final String categoryName;
  final String? typeId;
  final String? typeName;
}
