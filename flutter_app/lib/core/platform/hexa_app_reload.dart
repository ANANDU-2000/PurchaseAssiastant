// Full-page reload helper for unrecoverable layout/ErrorWidget recovery.
// Kept intentionally — sole call site: hexa_layout_error_widget.dart Reload.
export 'hexa_app_reload_stub.dart'
    if (dart.library.html) 'hexa_app_reload_web.dart';
