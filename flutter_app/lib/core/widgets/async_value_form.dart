import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keeps forms usable while providers refetch in the background.
extension AsyncValueFormX<T> on AsyncValue<T> {
  Widget whenForm({
    required Widget Function(T value) data,
    required Widget Function() initialLoading,
    Widget Function(Object error, StackTrace stackTrace)? error,
    Widget Function(T value)? reloadingBanner,
  }) {
    final cached = valueOrNull;
    return when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () {
        if (cached != null) {
          if (reloadingBanner != null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                reloadingBanner(cached),
                data(cached),
              ],
            );
          }
          return data(cached);
        }
        return initialLoading();
      },
      error: error ??
          (e, st) {
            if (cached != null) return data(cached);
            return initialLoading();
          },
      data: data,
    );
  }
}

/// Linear progress for inline form sections during background reload.
Widget formReloadBanner() => const LinearProgressIndicator(minHeight: 2);
