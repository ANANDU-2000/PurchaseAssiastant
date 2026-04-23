import 'package:flutter/material.dart';

import '../../../../core/theme/hexa_colors.dart';

/// Filled light-grey fields, soft border, 10px radius — shared login / register.
InputDecoration authFilledDecoration(
  String hint, {
  required IconData icon,
  bool err = false,
  Widget? suffix,
}) {
  return InputDecoration(
    filled: true,
    fillColor: const Color(0xFFF3F4F6),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    hintText: hint,
    hintStyle: TextStyle(
      fontSize: 15,
      color: Colors.grey.shade500,
      fontWeight: FontWeight.w400,
    ),
    prefixIcon: Icon(icon, size: 20, color: Colors.grey.shade600),
    prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    suffixIcon: suffix,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: err ? Colors.red.shade500 : const Color(0xFFE5E7EB),
        width: err ? 1.5 : 1,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: HexaColors.brandPrimary, width: 1.5),
    ),
  );
}
