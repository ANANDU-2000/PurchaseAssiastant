// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web: hard reload — used only from the layout ErrorWidget "Reload" action.
void reloadHexaApp() {
  html.window.location.reload();
}
