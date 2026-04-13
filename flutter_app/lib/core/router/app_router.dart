import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/session_notifier.dart';
import 'page_transitions.dart';
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
import '../../features/notifications/presentation/notifications_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/shell/shell_screen.dart';
import '../../features/splash/presentation/splash_page.dart';
final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: authRefresh,
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not open this page.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    ),
    redirect: (context, state) {
      ProviderContainer container;
      try {
        container = ProviderScope.containerOf(context);
      } catch (_) {
        // First frame / wrong ancestor — don't block navigation.
        return null;
      }
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
      GoRoute(
        path: '/splash',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const SplashPage(),
        ),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const LoginPage(),
        ),
      ),
      GoRoute(
        path: '/catalog',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const CatalogPage(),
        ),
      ),
      GoRoute(
        path: '/catalog/item/:itemId',
        pageBuilder: (context, state) {
          final id = state.pathParameters['itemId']!;
          return iosPushPage(
            key: state.pageKey,
            child: CatalogItemDetailPage(itemId: id),
          );
        },
      ),
      GoRoute(
        path: '/catalog/category/:categoryId',
        pageBuilder: (context, state) {
          final id = state.pathParameters['categoryId']!;
          return iosPushPage(
            key: state.pageKey,
            child: CatalogCategoryDetailPage(categoryId: id),
          );
        },
      ),
      GoRoute(
        path: '/entry/:entryId',
        pageBuilder: (context, state) {
          final id = state.pathParameters['entryId']!;
          return iosPushPage(
            key: state.pageKey,
            child: EntryDetailPage(entryId: id),
          );
        },
      ),
      GoRoute(
        path: '/supplier/:supplierId',
        pageBuilder: (context, state) {
          final id = state.pathParameters['supplierId']!;
          return iosPushPage(
            key: state.pageKey,
            child: SupplierDetailPage(supplierId: id),
          );
        },
      ),
      GoRoute(
        path: '/broker/:brokerId',
        pageBuilder: (context, state) {
          final id = state.pathParameters['brokerId']!;
          return iosPushPage(
            key: state.pageKey,
            child: BrokerDetailPage(brokerId: id),
          );
        },
      ),
      GoRoute(
        path: '/contacts/category',
        pageBuilder: (context, state) {
          final raw = state.uri.queryParameters['name'] ?? '';
          return iosPushPage(
            key: state.pageKey,
            child: CategoryItemsPage(category: Uri.decodeComponent(raw)),
          );
        },
      ),
      GoRoute(
        path: '/item-analytics/:itemKey',
        pageBuilder: (context, state) {
          final enc = state.pathParameters['itemKey']!;
          final name = Uri.decodeComponent(enc);
          return iosPushPage(
            key: state.pageKey,
            child: ItemAnalyticsDetailPage(itemName: name),
          );
        },
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const SettingsPage(),
        ),
      ),
      // In-app AI chat hidden for end users (WhatsApp bot is primary). Route kept for future flag.
      GoRoute(
        path: '/ai',
        name: 'ai',
        redirect: (context, state) => '/home',
      ),
      GoRoute(
        path: '/notifications',
        name: 'notifications',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const NotificationsPage(),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ShellScreen(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                  path: '/home',
                  name: 'home',
                  builder: (context, state) => const HomePage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                  path: '/entries',
                  name: 'entries',
                  builder: (context, state) => const EntriesPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                  path: '/contacts',
                  name: 'contacts',
                  builder: (context, state) => const ContactsPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                  path: '/analytics',
                  name: 'analytics',
                  builder: (context, state) => const AnalyticsPage()),
            ],
          ),
        ],
      ),
    ],
  );
});
