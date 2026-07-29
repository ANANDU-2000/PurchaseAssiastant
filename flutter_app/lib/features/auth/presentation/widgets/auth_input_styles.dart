import 'package:flutter/material.dart';

import '../../../../core/theme/hexa_colors.dart';

/// Filled light-grey fields, soft border, 10px radius — shared login / register.
InputDecoration authFilledDecoration(
  String hint, {
  required IconData icon,
  bool err = false,
  String? errorText,
  Widget? suffix,
}) {
  final hasErr = err || (errorText != null && errorText.isNotEmpty);
  final errSide = BorderSide(color: Colors.red.shade500, width: 1.5);
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
    errorText: errorText,
    errorStyle: TextStyle(
      color: Colors.red.shade700,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ),
    prefixIcon: Icon(icon, size: 20, color: Colors.grey.shade600),
    prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    suffixIcon: suffix,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: hasErr
          ? errSide
          : const BorderSide(color: HexaColors.inputBorderGrey, width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: hasErr
          ? errSide
          : const BorderSide(color: HexaColors.brandPrimary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: errSide,
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: errSide,
    ),
  );
}
