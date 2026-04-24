// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

bool _removed = false;

/// Hides the static `#boot` label from [web/index.html] once Flutter has painted.
void removeBootOverlayIfPresent() {
  if (_removed) return;
  _removed = true;
  html.document.getElementById('boot')?.remove();
}
