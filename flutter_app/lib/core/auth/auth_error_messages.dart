import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// When the browser cannot open a TCP connection to the API (backend not running / wrong host).
String? _connectionUnreachableHint(DioException e) {
  final blob = '${e.message} ${e.error}';
  final lower = blob.toLowerCase();
  if (lower.contains('connection refused') ||
      lower.contains('err_connection_refused') ||
      lower.contains('failed to connect') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection reset') ||
      lower.contains('connection timed out') ||
      lower.contains('timed out')) {
    return "Can't reach the sign-in server. Start the API on your machine (or point this app to the right address), then try again.";
  }
  return null;
}

/// Web-only: Dio often reports CORS / fetch failures as unknown + empty body.
String? _webBrowserNetworkHint(DioException e) {
  final blob = '${e.message} ${e.error}'.toLowerCase();
  if (blob.contains('failed to fetch') ||
      blob.contains('xmlhttprequest') ||
      blob.contains('networkerror') ||
      blob.contains('clientexception') ||
      blob.contains('load failed') ||
      blob.contains('err_network') ||
      blob.contains('cors')) {
    return "The browser couldn't reach the sign-in API. "
        "Start the backend (uvicorn from the backend folder), wait until it is listening, "
        "then refresh this page. "
        "For Flutter web, use http://127.0.0.1 or http://localhost for both the app and API_BASE_URL — they must match the host style. "
        "Production: set CORS_ORIGINS to your deployed web origin.";
  }
  return null;
}

/// User-safe copy for auth and network failures (no URLs, env names, or raw exceptions).
String friendlyAuthError(
  Object error, {
  required AuthErrorContext context,
}) {
  if (error is DioException) {
    // Reachability first: no HTTP body / wrong host / API stopped — not "wrong password".
    if (_isNetworkError(error)) {
      final hint = _connectionUnreachableHint(error);
      if (hint != null) return hint;
      if (kIsWeb) {
        final web = _webBrowserNetworkHint(error);
        if (web != null) return web;
        return "Sign-in couldn't reach the API from this browser. "
            "Confirm the backend is running on http://127.0.0.1:8000 and that CORS allows this origin (CORS_ORIGINS on the server).";
      }
      return "Can't connect right now. Check your internet and try again.";
    }

    final sc = error.response?.statusCode;
    if (sc == 401) {
      return context == AuthErrorContext.register
          ? 'Could not create your account. Check your details and try again.'
          : 'Wrong email or password for this server. Try again, or use Create Account if you have not registered here yet (a new database starts empty).';
    }
    if (sc == 400 || sc == 422) {
      return context == AuthErrorContext.register
          ? 'Please check your details and try again.'
          : 'Something was not right with that sign-in. Try again.';
    }
    if (sc == 409) {
      return context == AuthErrorContext.register
          ? 'This email or username is already registered on this server. Use the Sign In tab with your password, or pick a different email or username.'
          : 'That email or username is already taken.';
    }
    if (sc == 503) {
      return 'Sign-in is temporarily unavailable. Try again in a moment.';
    }
    if (sc != null && sc >= 500) {
      return 'Something went wrong on our side. Please try again in a moment.';
    }
  }
  return 'Something went wrong. Please try again.';
}

String friendlyGoogleSignInError(Object error) {
  if (error is DioException) {
    if (_isNetworkError(error)) {
      final hint = _connectionUnreachableHint(error);
      if (hint != null) return '$hint You can try email sign-in instead.';
      if (kIsWeb) {
        final web = _webBrowserNetworkHint(error);
        if (web != null) return '$web You can try email sign-in instead.';
        return "Google sign-in couldn't reach the server from this page. Try email sign-in after the API is running.";
      }
      return "Can't connect right now. Check your internet and try again.";
    }

    final sc = error.response?.statusCode;
    if (sc == 401) {
      return 'Google sign-in could not be verified. Try email sign-in instead.';
    }
    if (sc == 503) {
      return 'Sign-in is temporarily unavailable. Try again in a moment.';
    }
    if (sc != null && sc >= 500) {
      return 'Something went wrong on our side. Please try again in a moment.';
    }
  }
  return 'Google sign-in did not work. Try again or use email sign-in.';
}

bool _isNetworkError(DioException e) {
  // badResponse = HTTP error status; never treat as "offline" (even if body is empty).
  if (e.type == DioExceptionType.badResponse) return false;
  if (e.response != null) return false;
  final t = e.type;
  return t == DioExceptionType.connectionTimeout ||
      t == DioExceptionType.sendTimeout ||
      t == DioExceptionType.receiveTimeout ||
      t == DioExceptionType.connectionError ||
      (t == DioExceptionType.unknown && e.response == null);
}

enum AuthErrorContext { login, register }

/// Short user-facing copy for failed API calls in SnackBars and dialogs (no stack traces or raw response dumps).
///
/// Set [forAssistant] for the in-app Assistant tab — clearer copy when the LLM endpoint fails.
String friendlyApiError(Object error, {bool forAssistant = false}) {
  if (error is DioException) {
    final sc = error.response?.statusCode;
    if (sc == 401 || sc == 403) {
      return forAssistant
          ? 'Assistant could not verify your session. Open Settings or sign in again.'
          : 'You may need to sign in again.';
    }
    if (sc == 404) {
      return 'That record was not found. Try refreshing.';
    }
    if (sc == 409) {
      return 'That conflicts with existing data. Try again.';
    }
    if (sc == 400 || sc == 422) {
      return 'Please check your input and try again.';
    }
    if (sc == 503) {
      return forAssistant
          ? 'Assistant is temporarily unavailable. Try again in a moment.'
          : 'Service is temporarily unavailable. Try again shortly.';
    }
    if (sc != null && sc >= 500) {
      return forAssistant
          ? 'Assistant hit a server error. Please try again in a moment.'
          : 'Something went wrong on our side. Please try again.';
    }
    if (_isNetworkError(error)) {
      final hint = _connectionUnreachableHint(error);
      if (hint != null) {
        return forAssistant
            ? "Assistant couldn't reach the server. $hint"
            : hint;
      }
      if (kIsWeb) {
        final web = _webBrowserNetworkHint(error);
        if (web != null) {
          return forAssistant
              ? "Assistant couldn't reach the server. $web"
              : web;
        }
      }
      return forAssistant
          ? "Can't reach the assistant. Check your connection and try again."
          : "Can't connect right now. Check your internet and try again.";
    }
    return 'Request could not be completed. Try again.';
  }
  return 'Something went wrong. Please try again.';
}
