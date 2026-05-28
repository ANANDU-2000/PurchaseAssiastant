import 'package:flutter/material.dart';

import 'catalog_item_detail_page.dart';

class ItemEditPage extends StatelessWidget {
  const ItemEditPage({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    return CatalogItemDetailPage(
      itemId: itemId,
      startInEditMode: true,
    );
  }
}

