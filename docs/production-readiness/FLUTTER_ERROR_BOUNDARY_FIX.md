# Flutter error boundary fix

## Problem (historical)

A root `FlutterError.onError` handler that always called `setState` with the exception caused **RenderFlex overflow** and similar framework assertions to replace the **entire** app with “Something went wrong loading the app.” **Retry** cleared local state but users could still feel trapped if navigation state was wrong; layout errors should never warrant a global app replacement in production.

## Implementation

**File:** [`flutter_app/lib/app.dart`](../../flutter_app/lib/app.dart)

1. **`_hexaFlutterErrorLikelyNonFatal(FlutterErrorDetails details)`**  
   Returns true when `details.silent` is true, or when `details.exceptionAsString()` contains any of: `RenderFlex`, `overflowed`, `BoxConstraints`, `viewport`.

2. **`_HexaErrorBoundaryState.initState`**  
   - Saves previous `FlutterError.onError`.  
   - New handler: forwards to `_previousOnError`, then if `mounted` and **not** (`!kDebugMode && _hexaFlutterErrorLikelyNonFatal(details)`), sets `_error` from `details.exception`.  
   - Meaning: **debug** still surfaces all errors to the boundary (developer visibility). **Release/profile** skips the heuristic “non-fatal” class from replacing the whole tree.

3. **Recovery UI**  
   - **Retry:** `_clearError()` only.  
   - **Go to Home:** `_clearError()` then `widget.onGoHome()`.

4. **`HexaApp` wiring**  
   `onGoHome: () => ref.read(appRouterProvider).go('/home')` so recovery resets to a known shell route.

5. **Platform async hook (non-widget errors)** — [`flutter_app/lib/main.dart`](../../flutter_app/lib/main.dart)  
   After `WidgetsFlutterBinding.ensureInitialized()`, `_installHexaPlatformAsyncErrorHook()` chains any existing `PlatformDispatcher.instance.onError`, then returns `true` (handled) for **benign** errors: `DioException`, `TimeoutException`, and string patterns for socket / client / handshake / host lookup failures.  
   This is **orthogonal** to the `_HexaErrorBoundary` in `app.dart` (which only sees `FlutterError.onError`). It does **not** show UI — network/PDF flows should still use SnackBars at the call site.

## Design notes

- This boundary is a **last resort**, not the primary error UX. Network and PDF flows should still catch at the call site (see [PDF_EXPORT_HARDENING.md](PDF_EXPORT_HARDENING.md)).
- Heuristic string matching can miss novel non-fatal messages or incorrectly treat a rare fatal as non-fatal; treat changes here as high-review.

## How to verify

1. In **release** or **profile** on device, introduce a contained overflow in a throwaway branch: UI should **not** swap to the orange warning screen for that overflow string class.  
2. In **debug**, confirm the boundary still catches for quick iteration.  
3. Tap **Go to Home** from the error screen: confirm navigation lands on `/home` and UI is interactive.

## Related

- [CRITICAL_RUNTIME_FAILURES.md](CRITICAL_RUNTIME_FAILURES.md)
