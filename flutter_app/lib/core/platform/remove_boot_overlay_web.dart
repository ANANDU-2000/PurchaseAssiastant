// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

bool _removed = false;

/// Hides the static `#boot` / `#splash` overlays from [web/index.html] once Flutter
/// has painted bootstrap UI (not on the engine's empty first frame).
void removeBootOverlayIfPresent({bool force = false}) {
  if (_removed && !force) return;
  void hide() {
    html.document.getElementById('boot')?.remove();
    final splash = html.document.getElementById('splash');
    if (splash == null) return;
    if (splash.dataset['dismissed'] == '1') return;
    splash.dataset['dismissed'] = '1';
    splash.classes.add('removing');
    Future<void>.delayed(const Duration(milliseconds: 280), () {
      splash.remove();
    });
  }

  // Two animation frames so the first painted route (spinner/login/shell) is on canvas
  // before we remove the HTML splash — avoids a blank gray gap on desktop web.
  html.window.requestAnimationFrame((_) {
    html.window.requestAnimationFrame((_) {
      _removed = true;
      hide();
    });
  });
}
