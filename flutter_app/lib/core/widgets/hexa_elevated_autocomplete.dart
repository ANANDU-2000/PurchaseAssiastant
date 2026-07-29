import 'package:flutter/material.dart';

/// Autocomplete dropdown that paints above list rows / buttons (z-index fix).
Widget hexaElevatedAutocompleteOptions<T extends Object>(
  BuildContext context,
  AutocompleteOnSelected<T> onSelected,
  Iterable<T> options, {
  required String Function(T value) label,
  double maxHeight = 240,
}) {
  final list = options.toList(growable: false);
  if (list.isEmpty) return const SizedBox.shrink();
  // Prefer the Autocomplete field width when the overlay reports it; fall back
  // to a sane viewport-relative cap so desktop sidebars are not ignored.
  return LayoutBuilder(
    builder: (context, constraints) {
      final mqW = MediaQuery.sizeOf(context).width;
      final reported = constraints.maxWidth;
      final width = reported.isFinite && reported > 40
          ? reported
          : (mqW > 720 ? 480.0 : mqW - 24).clamp(160.0, mqW);
      return Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 12,
          shadowColor: Colors.black38,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: width),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final opt = list[index];
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text(
                    label(opt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () => onSelected(opt),
                );
              },
            ),
          ),
        ),
      );
    },
  );
}
