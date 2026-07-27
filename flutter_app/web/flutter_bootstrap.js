// Custom bootstrap: load CanvasKit from this origin (/canvaskit/) instead of gstatic CDN.
// Requires: flutter run -d chrome --no-web-resources-cdn
// Tokens are filled in by `flutter run` / `flutter build web`.
{{flutter_js}}
{{flutter_build_config}}

// Use 'chromium' variant for Chrome/Edge (smaller WASM, uses ImageDecoder API).
// Fall back to 'full' for Firefox, Safari, and embedded browsers that lack ImageDecoder.
// This reduces the initial WASM download by ~1.8 MB for Chrome/Edge users.
var _ckVariant = 'full';
try {
  if (typeof ImageDecoder !== 'undefined' && /Chrome|Edg/.test(navigator.userAgent)) {
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
