import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_responsive.dart';

/// Compact search row (no duplicate filter control).
class StockInlineSearchBar extends StatelessWidget {
  const StockInlineSearchBar({
    super.key,
    required this.controller,
    required this.onClear,
  });

  final TextEditingController controller;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        HexaResponsive.pageGutter(context, operational: true),
        4,
        HexaResponsive.pageGutter(context, operational: true),
        4,
      ),
      child: SizedBox(
        height: 40,
        child: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search item, code, barcode…',
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: 'Clear',
              onPressed: onClear,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFD8D5D0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFD8D5D0)),
            ),
          ),
        ),
      ),
    );
  }
}
