import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import 'widgets/scan_item_stock_summary_card.dart';

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
        title: const Text('Item stock'),
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
          final category = data['category']?.toString() ?? 'Catalog item';
          final code = data['item_code']?.toString() ?? '—';
          final rack = data['rack_location']?.toString() ?? '—';
          final status = (data['status']?.toString() ?? 'healthy')
              .replaceAll('_', ' ')
              .toUpperCase();

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                category,
                style: HexaDsType.body(14, color: HexaDsColors.textMuted),
              ),
              const SizedBox(height: 12),
              ScanItemStockSummaryCard(item: data),
              const SizedBox(height: 12),
              Text('Item code: $code', style: HexaDsType.bodySm(context)),
              Text('Rack: $rack', style: HexaDsType.bodySm(context)),
              const SizedBox(height: 8),
              Text(
                'Status: $status',
                style: HexaDsType.label(12, color: HexaDsColors.textMuted),
              ),
              const SizedBox(height: 16),
              Text(
                'Read-only · open the Harisree app to update physical or system stock.',
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
