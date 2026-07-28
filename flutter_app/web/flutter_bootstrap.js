// Custom bootstrap: load CanvasKit from this origin (/canvaskit/) instead of gstatic CDN.
// Requires: flutter run -d chrome --no-web-resources-cdn
// Tokens are filled in by `flutter run` / `flutter build web`.
{{flutter_js}}
{{flutter_build_config}}

// Prefer full CanvasKit — the chromium/ImageDecoder variant can fail to
// attach a scene in some embedded Chromium hosts (blank glass pane, 0 canvas).
var _ckVariant = 'full';
try {
  // Keep chromium only for real Chrome/Edge desktop when ImageDecoder exists.
  var ua = navigator.userAgent || '';
  var embedded = /Cursor|Electron|Edg\/.*Electron/i.test(ua);
  if (!embedded && typeof ImageDecoder !== 'undefined' && /Chrome|Edg/.test(ua)) {
    _ckVariant = 'chromium';
  }
} catch (e) {}

const _flutterLoaderConfig = {
  canvasKitBaseUrl: '/canvaskit/',
  canvasKitVariant: _ckVariant,
};

_flutter.loader.load({
  config: _flutterLoaderConfig,
  onEntrypointLoaded: async function (engineInitializer) {
    const boot = document.getElementById('boot');
    try {
      const appRunner = await engineInitializer.initializeEngine(_flutterLoaderConfig);
      // Do not await runApp before removing #boot: async main() keeps the promise pending
      // until heavy init finishes, so "Starting…" looked like a frozen white screen.
      const finished = appRunner.runApp();
      // Keep #boot / #splash until Dart paints bootstrap UI (removeBootOverlayIfPresent).
      await finished;
    } catch (e) {
      console.error(e);
      const b = document.getElementById('boot');
      if (b) {
        b.style.color = '#f87171';
        b.style.pointerEvents = 'auto';
        b.textContent = 'App failed to start. See the browser console for details.';
      }
    }
  },
});
