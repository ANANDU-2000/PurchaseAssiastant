import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/widgets/app_button.dart';
import '../../../../core/design_system/widgets/app_form_layout.dart';
import '../../../../core/design_system/widgets/app_text_field.dart';
import '../../../../core/providers/business_aggregates_invalidation.dart';
import '../../../../core/providers/catalog_providers.dart';
import '../../../../core/providers/trade_purchases_provider.dart';
import '../../../../core/utils/item_code_format.dart';
import '../../../../core/widgets/form_field_scroll.dart';
import '../../../../shared/widgets/bag_default_unit_hint.dart';
import '../../../../shared/widgets/search_picker_sheet.dart';

/// Full-screen / sheet body for editing catalog item defaults (name, unit, costs).
class CatalogItemDefaultsEditForm extends StatefulWidget {
  const CatalogItemDefaultsEditForm({
    super.key,
    required this.pickerContext,
    required this.nameCtrl,
    required this.codeCtrl,
    required this.hsnCtrl,
    required this.taxCtrl,
    required this.kgCtrl,
    required this.wptCtrl,
    required this.landCtrl,
    required this.sellCtrl,
    required this.initialUnit,
    this.scrollController,
    this.showHeader = false,
    this.openingStockLabel,
    this.canSetOpeningStock = false,
    this.onSetOpeningStock,
    this.nameError,
    this.kgError,
  });

  final BuildContext pickerContext;
  final TextEditingController nameCtrl;
  final TextEditingController codeCtrl;
  final TextEditingController hsnCtrl;
  final TextEditingController taxCtrl;
  final TextEditingController kgCtrl;
  final TextEditingController wptCtrl;
  final TextEditingController landCtrl;
  final TextEditingController sellCtrl;
  final String? initialUnit;
  final ScrollController? scrollController;
  final bool showHeader;
  /// e.g. "0 KG" or "120 KG · set 3d ago"
  final String? openingStockLabel;
  final bool canSetOpeningStock;
  final VoidCallback? onSetOpeningStock;
  final String? nameError;
  final String? kgError;

  @override
  State<CatalogItemDefaultsEditForm> createState() =>
      CatalogItemDefaultsEditFormState();
}

class CatalogItemDefaultsEditFormState
    extends State<CatalogItemDefaultsEditForm> {
  late String? _unit;
  late final FocusNode _nameFocus;
  late final FocusNode _codeFocus;
  late final FocusNode _hsnFocus;
  late final FocusNode _taxFocus;
  late final FocusNode _kgFocus;
  late final FocusNode _wptFocus;
  late final FocusNode _landFocus;
  late final FocusNode _sellFocus;

  @override
  void initState() {
    super.initState();
    _unit = widget.initialUnit;
    if (_nameLooksLikeBox(widget.nameCtrl.text) &&
        (_unit == null || _unit == 'piece')) {
      _unit = 'box';
    }
    _nameFocus = FocusNode();
    _codeFocus = FocusNode();
    _hsnFocus = FocusNode();
    _taxFocus = FocusNode();
    _kgFocus = FocusNode();
    _wptFocus = FocusNode();
    _landFocus = FocusNode();
    _sellFocus = FocusNode();
    for (final f in [
      _nameFocus,
      _codeFocus,
      _hsnFocus,
      _taxFocus,
      _kgFocus,
      _wptFocus,
      _landFocus,
      _sellFocus,
    ]) {
      bindFocusNodeScrollIntoView(f);
    }
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _codeFocus.dispose();
    _hsnFocus.dispose();
    _taxFocus.dispose();
    _kgFocus.dispose();
    _wptFocus.dispose();
    _landFocus.dispose();
    _sellFocus.dispose();
    super.dispose();
  }

  bool get _showKgPerBag =>
      _unit == 'bag' ||
      parseOptionalKgPerBag(widget.kgCtrl.text) != null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Outer ListView owns scroll — do not nest AppFormLayout scrollable here.
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (widget.showHeader) ...[
          Text(
            'Item identity, unit defaults, and pricing.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: HexaDsSpace.s2),
        ],
        _sectionTitle(context, 'Item identity'),
        AppTextField(
          controller: widget.nameCtrl,
          focusNode: _nameFocus,
          label: 'Name *',
          errorText: widget.nameError,
          textCapitalization: TextCapitalization.words,
          autofocus: true,
        ),
        const SizedBox(height: HexaDsSpace.s1),
        AppFormRow(
          children: [
            AppTextField(
              controller: widget.codeCtrl,
              focusNode: _codeFocus,
              label: 'Item code',
              helper: 'A-Z, 0-9, hyphen',
              inputFormatters: [ItemCodeInputFormatter()],
            ),
            AppTextField(
              controller: widget.hsnCtrl,
              focusNode: _hsnFocus,
              label: 'HSN code',
            ),
          ],
        ),
        const SizedBox(height: HexaDsSpace.s2),
        _sectionTitle(context, 'Unit & packaging'),
        AppFormRow(
          children: [
            AppTextField(
              controller: widget.taxCtrl,
              focusNode: _taxFocus,
              label: 'Tax %',
              helper: 'e.g. 5',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Default stock unit',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                AppSecondaryButton(
                  dense: true,
                  label: _unit == null ? '— (unspecified)' : '$_unit',
                  onPressed: () async {
                    const none = '__unit_none__';
                    final id = await showSearchPickerSheet<String>(
                      context: widget.pickerContext,
                      title: 'Default unit',
                      rows: const [
                        SearchPickerRow(
                            value: none, title: '— (unspecified)'),
                        SearchPickerRow(value: 'kg', title: 'kg'),
                        SearchPickerRow(value: 'bag', title: 'bag'),
                        SearchPickerRow(value: 'box', title: 'box'),
                        SearchPickerRow(value: 'tin', title: 'tin'),
                        SearchPickerRow(value: 'piece', title: 'piece'),
                      ],
                      selectedValue: _unit ?? none,
                    );
                    if (!mounted) return;
                    if (id != null) {
                      setState(() => _unit = id == none ? null : id);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
        if (_showKgPerBag) ...[
          const SizedBox(height: HexaDsSpace.s2),
          AppTextField(
            controller: widget.kgCtrl,
            focusNode: _kgFocus,
            label: _unit == 'bag' ? 'Kg per bag *' : 'Kg per bag (optional)',
            helper: _unit == 'bag'
                ? 'Required when stock unit is bag'
                : 'Set unit to bag if this item is stocked in bags',
            errorText: widget.kgError,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          if (_unit == 'bag') ...[
            const SizedBox(height: HexaDsSpace.s1),
            BagDefaultUnitHint(
              kgAlreadySet: () {
                final v = parseOptionalKgPerBag(widget.kgCtrl.text);
                return v != null && v > 0;
              }(),
            ),
          ],
        ],
        if (_unit == 'tin') ...[
          const SizedBox(height: HexaDsSpace.s2),
          AppTextField(
            controller: widget.wptCtrl,
            focusNode: _wptFocus,
            label: 'Liters / weight per tin',
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
        const SizedBox(height: HexaDsSpace.s2),
        _sectionTitle(context, 'Default pricing'),
        AppFormRow(
          children: [
            AppTextField(
              controller: widget.landCtrl,
              focusNode: _landFocus,
              label: 'Default landing (₹)',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            AppTextField(
              controller: widget.sellCtrl,
              focusNode: _sellFocus,
              label: 'Default selling (₹)',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        if (widget.openingStockLabel != null) ...[
          const SizedBox(height: HexaDsSpace.s2),
          _sectionTitle(context, 'Opening stock (system baseline)'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(HexaDsSpace.s2),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(HexaDsRadii.md),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.openingStockLabel!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: HexaDsSpace.xs),
                Text(
                  widget.canSetOpeningStock
                      ? 'Opening + committed purchases = system total on item page.'
                      : 'Only owner/admin can set opening stock. Staff use Update physical.',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.canSetOpeningStock &&
                    widget.onSetOpeningStock != null) ...[
                  const SizedBox(height: HexaDsSpace.s1),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: widget.onSetOpeningStock,
                      child: const Text('Set opening stock'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  static Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  String? get selectedUnit => _unit;

  static bool _nameLooksLikeBox(String name) {
    final u = name.trim().toUpperCase();
    return u.contains(' BOX') ||
        u.endsWith(' BOX') ||
        u.contains(' CTN') ||
        u.contains('CARTON');
  }
}

class CatalogItemDefaultsValidation {
  const CatalogItemDefaultsValidation({
    this.nameError,
    this.kgError,
  });

  final String? nameError;
  final String? kgError;

  bool get ok => nameError == null && kgError == null;
}

CatalogItemDefaultsValidation validateCatalogItemDefaults({
  required String? unit,
  required TextEditingController nameCtrl,
  required TextEditingController codeCtrl,
  required TextEditingController kgCtrl,
}) {
  String? nameError;
  String? kgError;

  if (nameCtrl.text.trim().isEmpty) {
    nameError = 'Item name is required';
  }

  final codeRaw = normalizeItemCode(codeCtrl.text);
  if (codeRaw.isNotEmpty && !isValidItemCode(codeRaw)) {
    nameError ??=
        'Use A-Z, 0-9, hyphen, underscore only for item code';
  }

  if (unit == 'bag') {
    final kgParsed = parseOptionalKgPerBag(kgCtrl.text);
    if (kgParsed == null || kgParsed <= 0) {
      kgError = 'Kg per bag is required when unit is bag';
    }
  }

  return CatalogItemDefaultsValidation(
    nameError: nameError,
    kgError: kgError,
  );
}

/// Persists catalog defaults from controllers. Returns true on success.
Future<bool> saveCatalogItemDefaults({
  required WidgetRef ref,
  required String itemId,
  required String? unit,
  required TextEditingController nameCtrl,
  required TextEditingController codeCtrl,
  required TextEditingController hsnCtrl,
  required TextEditingController taxCtrl,
  required TextEditingController kgCtrl,
  required TextEditingController wptCtrl,
  required TextEditingController landCtrl,
  required TextEditingController sellCtrl,
}) async {
  final session = ref.read(sessionProvider);
  if (session == null) return false;

  final validation = validateCatalogItemDefaults(
    unit: unit,
    nameCtrl: nameCtrl,
    codeCtrl: codeCtrl,
    kgCtrl: kgCtrl,
  );
  if (!validation.ok) {
    throw DioException(
      requestOptions: RequestOptions(path: ''),
      error: validation.kgError ??
          validation.nameError ??
          'Please check your input',
    );
  }

  final codeRaw = normalizeItemCode(codeCtrl.text);

  final kgParsed = unit == 'bag' ? parseOptionalKgPerBag(kgCtrl.text) : null;
  final tax = double.tryParse(taxCtrl.text.trim());
  final wpt = double.tryParse(wptCtrl.text.trim());
  final land = double.tryParse(landCtrl.text.trim());
  final sell = double.tryParse(sellCtrl.text.trim());
  try {
    await ref.read(hexaApiProvider).updateCatalogItem(
          businessId: session.primaryBusiness.id,
          itemId: itemId,
          name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
          itemCode: codeRaw.isEmpty ? '' : codeRaw,
          hsnCode: hsnCtrl.text.trim().isEmpty ? null : hsnCtrl.text.trim(),
          taxPercent: tax,
          defaultLandingCost: land,
          defaultSellingCost: sell,
          includeDefaultUnit: true,
          defaultUnit: unit,
          patchDefaultKgPerBag:
              unit == 'bag' && kgParsed != null && kgParsed > 0,
          defaultKgPerBag: kgParsed,
          patchDefaultItemsPerBox: unit == 'box',
          defaultItemsPerBox: unit == 'box' ? 1.0 : null,
          patchDefaultWeightPerTin: unit == 'tin' && wpt != null && wpt > 0,
          defaultWeightPerTin: wpt,
        );
    ref.invalidate(catalogItemDetailProvider(itemId));
    ref.invalidate(tradePurchasesCatalogIntelProvider);
    invalidateCatalogItemSaveSurfaces(ref, itemId: itemId);
    return true;
  } on DioException {
    rethrow;
  }
}
