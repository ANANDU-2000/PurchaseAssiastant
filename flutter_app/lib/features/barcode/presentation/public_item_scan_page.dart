import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/json_coerce.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/widgets/friendly_load_error.dart';

/// Read-only stock view for QR label scans (no login required).
class PublicItemScanPage extends StatefulWidget {
  const PublicItemScanPage({super.key, required this.token});

  final String token;

  @override
  State<PublicItemScanPage> createState() => _PublicItemScanPageState();
}

class _PublicItemScanPageState extends State<PublicItemScanPage> {
  late final Future<Map<String, dynamic>> _load;

  @override
  void initState() {
    super.initState();
    _load = _fetch();
  }

  Future<Map<String, dynamic>> _fetch() async {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.resolvedApiBaseUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
      ),
    );
    final res = await dio.get<Map<String, dynamic>>(
      '/public/items/${Uri.encodeComponent(widget.token)}.json',
    );
    return Map<String, dynamic>.from(res.data ?? const {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: const Text('Harisree Warehouse'),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
        automaticallyImplyLeading: false,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _load,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return FriendlyLoadError(
              message: 'Item not found or link expired.',
              onRetry: () => setState(() => _load = _fetch()),
            );
          }
          final data = snap.data ?? const {};
          final name = data['name']?.toString() ?? 'Item';
          final category = data['category']?.toString() ?? 'Catalog item';
          final unit = (data['stock_unit']?.toString() ?? 'unit').toUpperCase();
          final qty = coerceToDouble(data['current_stock']);
          final status = (data['status']?.toString() ?? 'healthy').replaceAll('_', ' ');
          final code = data['item_code']?.toString() ?? '—';
          final rack = data['rack_location']?.toString() ?? '—';

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        name,
                        style: HexaDsType.heading(22),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        category,
                        style: HexaDsType.body(14, color: HexaDsColors.textMuted),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5F2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'System stock',
                              style: HexaDsType.label(12, color: HexaDsColors.textMuted),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${formatStockQtyNumber(qty)} $unit',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0E4F46),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              status.toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFE65100),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('Item code: $code', style: HexaDsType.bodySm(context)),
                      Text('Rack: $rack', style: HexaDsType.bodySm(context)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Read-only view · sign in to the app to update stock.',
                textAlign: TextAlign.center,
                style: HexaDsType.body(12, color: HexaDsColors.textMuted),
              ),
            ],
          );
        },
      ),
    );
  }
}
