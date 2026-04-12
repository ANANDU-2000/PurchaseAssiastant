// Custom bootstrap: load CanvasKit from this origin (/canvaskit/) instead of gstatic CDN.
// Requires: flutter run -d chrome --no-web-resources-cdn
// Tokens are filled in by `flutter run` / `flutter build web`.
{{flutter_js}}
{{flutter_build_config}}

// Use full CanvasKit (not chromium/) so browsers without ImageDecoder / break
// iterators still load WASM — avoids a permanent white screen in some embedded browsers.
//
// CRITICAL: Engine init must receive the same `config` object. The default loader calls
// `engineInitializer.initializeEngine(config)` (see flutter_js entrypoint_loader.js). Calling
// `initializeEngine()` with no args breaks web startup (hang / blank canvas) even when DDC 930/930 OK.
const _flutterLoaderConfig = {
  canvasKitBaseUrl: '/canvaskit/',
  canvasKitVariant: 'full',
};

_flutter.loader.load({
  config: _flutterLoaderConfig,
  onEntrypointLoaded: async function (engineInitializer) {
    const boot = document.getElementById('boot');
    try {
      const appRunner = await engineInitializer.initializeEngine(_flutterLoaderConfig);
      await appRunner.runApp();
    } catch (e) {
      console.error(e);
      if (boot) {
        boot.style.color = '#f87171';
        boot.style.pointerEvents = 'auto';
        boot.textContent = 'App failed to start. See the browser console for details.';
      }
      return;
    }
    boot?.remove();
  },
});
