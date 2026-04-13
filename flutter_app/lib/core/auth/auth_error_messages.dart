import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// When the browser cannot open a TCP connection to the API (backend not running / wrong host).
String? _connectionUnreachableHint(DioException e) {
  final blob = '${e.message} ${e.error}';
  final lower = blob.toLowerCase();
  if (lower.contains('connection refused') ||
      lower.contains('err_connection_refused') ||
      lower.contains('failed to connect') ||
      lower.contains('network is unreachable')) {
    return "Can't reach the sign-in server. Start the API on your machine (or point this app to the right address), then try again.";
  }
  return null;
}

/// User-safe copy for auth and network failures (no URLs, env names, or raw exceptions).
String friendlyAuthError(
  Object error, {
  required AuthErrorContext context,
}) {
  if (error is DioException) {
    final sc = error.response?.statusCode;
    if (sc == 401) {
      return context == AuthErrorContext.register
          ? 'Could not create your account. Check your details and try again.'
          : 'Email or password does not match. Try again or create an account.';
    }
    if (sc == 400 || sc == 422) {
      return context == AuthErrorContext.register
          ? 'Please check your details and try again.'
          : 'Something was not right with that sign-in. Try again.';
    }
    if (sc == 409) {
      return 'That email or username is already taken.';
    }
    if (sc == 503) {
      return 'Sign-in is temporarily unavailable. Try again in a moment.';
    }
    if (sc != null && sc >= 500) {
      return 'Something went wrong on our side. Please try again in a moment.';
    }
    if (_isNetworkError(error)) {
      final hint = _connectionUnreachableHint(error);
      if (hint != null) return hint;
      if (kIsWeb) {
        return "Sign-in couldn't load from this page. Check your connection. In production, the API must list this site's URL in CORS (CORS_ORIGINS).";
      }
      return "Can't connect right now. Check your internet and try again.";
    }
  }
  return 'Something went wrong. Please try again.';
}

String friendlyGoogleSignInError(Object error) {
  if (error is DioException) {
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
    if (_isNetworkError(error)) {
      final hint = _connectionUnreachableHint(error);
      if (hint != null) return '$hint You can try email sign-in instead.';
      if (kIsWeb) {
        return "Google sign-in couldn't reach the server from this page. Try email sign-in, or ask your admin to allow this site in API CORS settings.";
      }
      return "Can't connect right now. Check your internet and try again.";
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
String friendlyApiError(Object error) {
  if (error is DioException) {
    final sc = error.response?.statusCode;
    if (sc == 401 || sc == 403) {
      return 'You may need to sign in again.';
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
      return 'Service is temporarily unavailable. Try again shortly.';
    }
    if (sc != null && sc >= 500) {
      return 'Something went wrong on our side. Please try again.';
    }
    if (_isNetworkError(error)) {
      return "Can't connect right now. Check your internet and try again.";
    }
    return 'Request could not be completed. Try again.';
  }
  return 'Something went wrong. Please try again.';
}
