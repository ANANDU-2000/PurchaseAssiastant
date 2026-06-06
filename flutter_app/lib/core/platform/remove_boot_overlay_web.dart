// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

bool _removed = false;

/// Hides the static `#boot` / `#splash` overlays from [web/index.html] once Flutter
/// has painted bootstrap UI (not on the engine's empty first frame).
void removeBootOverlayIfPresent() {
  if (_removed) return;
  _removed = true;
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

  // One animation frame after Dart build so the canvas shows spinner/login shell.
  html.window.requestAnimationFrame((_) {
    hide();
  });
}
