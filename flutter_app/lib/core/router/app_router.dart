import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/session_notifier.dart';
import 'page_transitions.dart';
import '../../features/analytics/presentation/analytics_page.dart';
import '../../features/analytics/presentation/full_reports_page.dart';
import '../../features/analytics/presentation/item_analytics_detail_page.dart';
import '../../features/catalog/presentation/catalog_category_detail_page.dart';
import '../../features/catalog/presentation/catalog_item_detail_page.dart';
import '../../features/catalog/presentation/catalog_page.dart';
import '../../features/catalog/presentation/catalog_type_items_page.dart';
import '../../features/assistant/presentation/assistant_chat_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/signup_page.dart';
import '../../features/contacts/presentation/broker_detail_page.dart';
import '../../features/contacts/presentation/category_items_page.dart';
import '../../features/contacts/presentation/supplier_create_wizard_page.dart';
import '../../features/contacts/presentation/supplier_detail_page.dart';
import '../../features/entries/presentation/entry_detail_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/purchase/presentation/purchase_detail_page.dart';
import '../../features/purchase/presentation/purchase_home_page.dart';
import '../../features/purchase/presentation/purchase_wizard_page.dart';
import '../../features/notifications/presentation/notifications_page.dart';
import '../../features/settings/presentation/business_profile_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/search/presentation/search_page.dart';
import '../../features/shell/shell_screen.dart';
import '../../features/splash/presentation/splash_page.dart';
import '../../features/get_started/presentation/get_started_page.dart';
import '../../features/voice/presentation/voice_page.dart';

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
      final loc = state.matchedLocation;
      final public = loc == '/splash' ||
          loc == '/get-started' ||
          loc == '/login' ||
          loc == '/signup';

      ProviderContainer container;
      try {
        container = ProviderScope.containerOf(context);
      } catch (_) {
        // Rare: router runs before ProviderScope is available. Never land on a protected shell route.
        if (!public) return '/splash';
        return null;
      }

      final session = container.read(sessionProvider);
      // No session → only public auth/onboarding routes. (JWT may still be restoring in main(); splash handles that.)
      if (session == null) {
        if (public) return null;
        return '/login';
      }
      // Signed in → skip auth screens.
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
        path: '/get-started',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const GetStartedPage(),
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
        path: '/signup',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const SignupPage(),
        ),
      ),
      GoRoute(
        path: '/search',
        name: 'search',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const SearchPage(),
        ),
      ),
      // Aliases
      GoRoute(path: '/dashboard', redirect: (_, __) => '/home'),
      GoRoute(path: '/history', redirect: (_, __) => '/purchase'),
      GoRoute(path: '/contacts', redirect: (_, __) => '/purchase'),
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
        path: '/catalog/category/:categoryId/type/:typeId',
        pageBuilder: (context, state) {
          final cid = state.pathParameters['categoryId']!;
          final tid = state.pathParameters['typeId']!;
          return iosPushPage(
            key: state.pageKey,
            child: CatalogTypeItemsPage(categoryId: cid, typeId: tid),
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
      GoRoute(
        path: '/settings/business',
        name: 'settings_business',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const BusinessProfilePage(),
        ),
      ),
      GoRoute(
        path: '/ai',
        redirect: (context, state) => '/assistant',
      ),
      GoRoute(
        path: '/entries',
        redirect: (context, state) => '/purchase',
      ),
      GoRoute(
        path: '/reports',
        name: 'reports_full',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const FullReportsPage(),
        ),
      ),
      GoRoute(
        path: '/purchase/new',
        name: 'purchase_new',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const PurchaseWizardPage(),
        ),
      ),
      GoRoute(
        path: '/purchase/edit/:purchaseId',
        name: 'purchase_edit',
        pageBuilder: (context, state) {
          final id = state.pathParameters['purchaseId']!;
          return iosPushPage(
            key: state.pageKey,
            child: PurchaseWizardPage(editingId: id),
          );
        },
      ),
      GoRoute(
        path: '/purchase/detail/:purchaseId',
        name: 'purchase_detail',
        pageBuilder: (context, state) {
          final id = state.pathParameters['purchaseId']!;
          return iosPushPage(
            key: state.pageKey,
            child: PurchaseDetailPage(purchaseId: id),
          );
        },
      ),
      GoRoute(
        path: '/contacts/supplier/new',
        name: 'supplier_create',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const SupplierCreateWizardPage(),
        ),
      ),
      GoRoute(
        path: '/notifications',
        name: 'notifications',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const NotificationsPage(),
        ),
      ),
      GoRoute(
        path: '/voice',
        name: 'voice',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const VoicePage(),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ShellScreen(navigationShell: navigationShell),
        branches: [
          // Branch 0 — Home dashboard
          StatefulShellBranch(
            routes: [
              GoRoute(
                  path: '/home',
                  name: 'home',
                  builder: (context, state) => const HomePage()),
            ],
          ),
          // Branch 1 — Reports (analytics)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/analytics',
                name: 'analytics',
                builder: (context, state) => const AnalyticsPage(),
              ),
            ],
          ),
          // Branch 2 — History (purchase list)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/purchase',
                name: 'purchase',
                builder: (context, state) => const PurchaseHomePage(),
              ),
            ],
          ),
          // Branch 3 — Assistant
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/assistant',
                name: 'assistant',
                builder: (context, state) => const AssistantChatPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
