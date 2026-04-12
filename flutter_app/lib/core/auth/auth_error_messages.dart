import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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
      if (kIsWeb) {
        return "Can't complete sign-in from this page. Check your connection, or ask your admin to allow this app URL in the API CORS settings (backend CORS_ORIGINS).";
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
      if (kIsWeb) {
        return "Can't complete Google sign-in from this page. Check CORS allows this app URL, or try email sign-in.";
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
