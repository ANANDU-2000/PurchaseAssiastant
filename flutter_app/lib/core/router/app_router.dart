import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/session_notifier.dart';
import '../../features/analytics/presentation/analytics_page.dart';
import '../../features/analytics/presentation/item_analytics_detail_page.dart';
import '../../features/catalog/presentation/catalog_category_detail_page.dart';
import '../../features/catalog/presentation/catalog_item_detail_page.dart';
import '../../features/catalog/presentation/catalog_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/contacts/presentation/contacts_page.dart';
import '../../features/contacts/presentation/broker_detail_page.dart';
import '../../features/contacts/presentation/category_items_page.dart';
import '../../features/contacts/presentation/supplier_detail_page.dart';
import '../../features/entries/presentation/entries_page.dart';
import '../../features/entries/presentation/entry_detail_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/shell/shell_screen.dart';
import '../../features/splash/presentation/splash_page.dart';
import '../../features/voice/presentation/voice_page.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: authRefresh,
    redirect: (context, state) {
      final container = ProviderScope.containerOf(context);
      final session = container.read(sessionProvider);
      final loc = state.matchedLocation;
      final public = loc == '/splash' || loc == '/login';
      if (session == null) {
        if (public) return null;
        return '/login';
      }
      if (public) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(path: '/catalog', builder: (context, state) => const CatalogPage()),
      GoRoute(
        path: '/catalog/item/:itemId',
        builder: (context, state) {
          final id = state.pathParameters['itemId']!;
          return CatalogItemDetailPage(itemId: id);
        },
      ),
      GoRoute(
        path: '/catalog/category/:categoryId',
        builder: (context, state) {
          final id = state.pathParameters['categoryId']!;
          return CatalogCategoryDetailPage(categoryId: id);
        },
      ),
      GoRoute(
        path: '/contacts',
        name: 'contacts',
        builder: (context, state) => const ContactsPage(),
      ),
      GoRoute(
        path: '/entry/:entryId',
        builder: (context, state) {
          final id = state.pathParameters['entryId']!;
          return EntryDetailPage(entryId: id);
        },
      ),
      GoRoute(
        path: '/supplier/:supplierId',
        builder: (context, state) {
          final id = state.pathParameters['supplierId']!;
          return SupplierDetailPage(supplierId: id);
        },
      ),
      GoRoute(
        path: '/broker/:brokerId',
        builder: (context, state) {
          final id = state.pathParameters['brokerId']!;
          return BrokerDetailPage(brokerId: id);
        },
      ),
      GoRoute(
        path: '/contacts/category',
        builder: (context, state) {
          final raw = state.uri.queryParameters['name'] ?? '';
          return CategoryItemsPage(category: Uri.decodeComponent(raw));
        },
      ),
      GoRoute(
        path: '/item-analytics/:itemKey',
        builder: (context, state) {
          final enc = state.pathParameters['itemKey']!;
          final name = Uri.decodeComponent(enc);
          return ItemAnalyticsDetailPage(itemName: name);
        },
      ),
      // Full-screen settings (opened from AppBar actions, not shell strip) — 4 shell tabs: Home | Entries | AI | Reports
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ShellScreen(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', name: 'home', builder: (context, state) => const HomePage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/entries', name: 'entries', builder: (context, state) => const EntriesPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/ai', name: 'ai', builder: (context, state) => const VoicePage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/analytics', name: 'analytics', builder: (context, state) => const AnalyticsPage()),
            ],
          ),
        ],
      ),
    ],
  );
});
