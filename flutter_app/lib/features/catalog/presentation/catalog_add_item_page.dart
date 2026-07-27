import 'package:flutter/material.dart';

import 'catalog_item_create_page.dart';

/// Legacy route wrapper — delegates to unified [CatalogItemCreatePage].
class CatalogAddItemPage extends StatelessWidget {
  const CatalogAddItemPage({
    super.key,
    required this.categoryId,
    required this.typeId,
    this.defaultSupplierId,
    this.defaultBrokerId,
  });

  final String categoryId;
  final String typeId;
  final String? defaultSupplierId;
  final String? defaultBrokerId;

  @override
  Widget build(BuildContext context) {
    return CatalogItemCreatePage(
      presetCategoryId: categoryId,
      presetTypeId: typeId,
      defaultSupplierId: defaultSupplierId,
      defaultBrokerId: defaultBrokerId,
      returnResultOnSave: true,
    );
  }
}
