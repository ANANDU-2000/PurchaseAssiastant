# Global error boundary rewrite

## Problem

Minor framework errors (overflow, disposed widget, etc.) replaced the entire app with “Something went wrong loading the app.” Profile/debug builds were especially harsh because non-fatal filtering only ran in release.

## Root cause

`_HexaErrorBoundary` in `flutter_app/lib/app.dart` installed `FlutterError.onError` and called `setState` with a fatal layout for every error unless a short string heuristic matched **and** `!kDebugMode`.

## Fix

- Non-fatal classification now runs in **all** build modes when the heuristic matches (expanded substrings: `RenderViewport`, `ParentDataWidget`, deactivated widget, `setState() after dispose`, `UnmountedRefException`, ticker issues, etc.).
- For those cases the handler returns after `FlutterError.dumpErrorToConsole(details)` so engineers still get console output without nuking the widget tree.
- Screen-level retries remain on purchase detail (`FriendlyLoadError`), reports (`_bumpInvalidate` / empty cards), and PDF helpers (existing try/catch patterns).

## Verification

- Deliberately trigger a small `RenderFlex` overflow in a dev build: app shell should stay visible; console should show the error.
- Force a real bootstrap failure (rare): full-screen boundary should still appear only for unclassified errors.
