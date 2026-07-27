import 'package:intl/date_symbol_data_local.dart';

/// Ensures intl locale data is loaded before PDF/export date & currency formatting.
///
/// Without this, `DateFormat(..., 'en_IN')` throws [LocaleDataException].
Future<void> ensurePdfLocalesInitialized() async {
  if (_initialized) return;
  if (_initFuture != null) {
    await _initFuture;
    return;
  }
  _initFuture = _doInit();
  await _initFuture;
}

bool _initialized = false;
Future<void>? _initFuture;

Future<void> _doInit() async {
  try {
    await initializeDateFormatting('en_IN');
  } catch (_) {
    // Non-fatal: fall back to en below.
  }
  try {
    await initializeDateFormatting('en');
  } catch (_) {
    // Last resort: default intl behavior.
  }
  _initialized = true;
}
