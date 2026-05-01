import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/session_notifier.dart';
import 'page_transitions.dart';
import '../../features/analytics/presentation/full_reports_page.dart';
import '../../features/analytics/presentation/item_analytics_detail_page.dart';
import '../../features/catalog/presentation/catalog_add_category_page.dart';
import '../../features/catalog/presentation/catalog_add_item_page.dart';
import '../../features/catalog/presentation/catalog_add_subcategory_page.dart';
import '../../features/catalog/presentation/catalog_category_detail_page.dart';
import '../../features/catalog/presentation/catalog_item_detail_page.dart';
import '../../features/catalog/presentation/catalog_page.dart';
import '../../features/catalog/presentation/catalog_type_items_page.dart';
import '../../features/assistant/presentation/assistant_chat_page.dart';
import '../../features/auth/presentation/forgot_password_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/reset_password_page.dart';
import '../../features/auth/presentation/signup_page.dart';
import '../../features/contacts/presentation/broker_detail_page.dart';
import '../../features/contacts/presentation/broker_wizard_page.dart';
import '../../features/contacts/presentation/category_items_page.dart';
import '../../features/contacts/presentation/contacts_page.dart';
import '../../features/contacts/presentation/supplier_create_simple.dart';
import '../../features/contacts/presentation/supplier_detail_page.dart';
import '../../features/supplier/presentation/supplier_ledger_page.dart';
import '../../features/item/presentation/item_history_page.dart';
import '../../features/broker/presentation/broker_history_page.dart';
import '../../features/home/presentation/home_breakdown_list_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../providers/home_breakdown_tab_providers.dart' show homeBreakdownTabFromQuery, HomeBreakdownTab;
import '../../features/purchase/domain/purchase_draft.dart';
import '../../features/purchase/presentation/purchase_detail_page.dart';
import '../../features/purchase/presentation/purchase_home_page.dart';
import '../../features/purchase/presentation/purchase_entry_wizard_v2.dart';
import '../../features/purchase/presentation/scan_purchase_page.dart';
import '../../features/notifications/presentation/notifications_page.dart';
import '../../features/settings/presentation/business_profile_page.dart';
import '../../features/settings/presentation/maintenance_history_page.dart';
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
          loc == '/signup' ||
          loc == '/forgot-password' ||
          loc == '/reset-password';

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
      // Password reset from email should work even with a stale / other-tab session.
      final resetTok = state.uri.queryParameters['token']?.trim() ?? '';
      if (loc == '/reset-password' && resetTok.isNotEmpty) {
        return null;
      }
      // Allow forgot-password so users aren't bounced to /home if session state is wrong.
      if (loc == '/forgot-password') {
        return null;
      }
      // Signed in → skip other auth / onboarding screens.
      if (public) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => '/splash',
      ),
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
        path: '/forgot-password',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const ForgotPasswordPage(),
        ),
      ),
      GoRoute(
        path: '/reset-password',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: ResetPasswordPage(
            initialToken: state.uri.queryParameters['token'],
          ),
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
      GoRoute(
        path: '/contacts',
        name: 'contacts',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const ContactsPage(),
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
        path: '/catalog/new-category',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const CatalogAddCategoryPage(),
        ),
      ),
      GoRoute(
        path: '/catalog/category/:categoryId/new-subcategory',
        pageBuilder: (context, state) {
          final id = state.pathParameters['categoryId']!;
          return iosPushPage(
            key: state.pageKey,
            child: CatalogAddSubcategoryPage(categoryId: id),
          );
        },
      ),
      GoRoute(
        path: '/catalog/category/:categoryId/type/:typeId/add-item',
        pageBuilder: (context, state) {
          final cid = state.pathParameters['categoryId']!;
          final tid = state.pathParameters['typeId']!;
          return iosPushPage(
            key: state.pageKey,
            child: CatalogAddItemPage(categoryId: cid, typeId: tid),
          );
        },
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
        path: '/catalog/item/:itemId/purchase-history',
        pageBuilder: (context, state) {
          final id = state.pathParameters['itemId']!;
          return iosPushPage(
            key: state.pageKey,
            child: ItemHistoryPage(catalogItemId: id),
          );
        },
      ),
      GoRoute(
        path: '/catalog/item/:itemId/ledger',
        pageBuilder: (context, state) {
          final id = state.pathParameters['itemId']!;
          return iosPushPage(
            key: state.pageKey,
            child: ItemHistoryPage(catalogItemId: id),
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
        path: '/supplier/:supplierId/ledger',
        pageBuilder: (context, state) {
          final id = state.pathParameters['supplierId']!;
          return iosPushPage(
            key: state.pageKey,
            child: SupplierLedgerPage(supplierId: id),
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
        path: '/broker/:brokerId/ledger',
        pageBuilder: (context, state) {
          final id = state.pathParameters['brokerId']!;
          return iosPushPage(
            key: state.pageKey,
            child: BrokerHistoryPage(brokerId: id),
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
        path: '/settings/maintenance/history',
        name: 'settings_maintenance_history',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const MaintenanceHistoryPage(),
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
        path: '/analytics',
        redirect: (context, state) => '/reports',
      ),
      GoRoute(
        path: '/purchase/new',
        name: 'purchase_new',
        pageBuilder: (context, state) {
          final cid = state.uri.queryParameters['catalogItemId']?.trim();
          PurchaseDraft? seed;
          final ex = state.extra;
          if (ex is PurchaseDraft) seed = ex;
          return iosPushPage(
            key: ValueKey(
              'purchase_new_${seed != null ? 'seed' : ((cid != null && cid.isNotEmpty) ? cid : 'none')}',
            ),
            child: PurchaseEntryWizardV2(
              initialCatalogItemId:
                  (cid != null && cid.isNotEmpty) ? cid : null,
              initialDraft: seed,
            ),
          );
        },
      ),
      GoRoute(
        path: '/purchase/scan',
        name: 'purchase_scan',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const ScanPurchasePage(),
        ),
      ),
      GoRoute(
        path: '/purchase/edit/:purchaseId',
        name: 'purchase_edit',
        pageBuilder: (context, state) {
          final id = state.pathParameters['purchaseId']!;
          return iosPushPage(
            key: state.pageKey,
            child: PurchaseEntryWizardV2(editingId: id),
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
          child: const SupplierCreateSimple(),
        ),
      ),
      GoRoute(
        path: '/suppliers/quick-create',
        name: 'supplier_quick_create',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const SupplierCreateSimple(),
        ),
      ),
      GoRoute(
        path: '/brokers/quick-create',
        name: 'broker_quick_create',
        pageBuilder: (context, state) => iosPushPage(
          key: state.pageKey,
          child: const BrokerWizardPage(selectionReturnOnSave: true),
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
      // Main app tabs: keep navigation in this shell only; use `navigationShell.goBranch`
      // or `context.go('/home'|'/reports'|...)` — avoid `push` onto the root stack for these paths
      // or the active tab and visible content can disagree.
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
                builder: (context, state) => const HomePage(),
                routes: [
                  GoRoute(
                    path: 'breakdown-more',
                    name: 'home_breakdown_more',
                    builder: (context, state) {
                      final tab = homeBreakdownTabFromQuery(
                            state.uri.queryParameters['tab'],
                          ) ??
                          HomeBreakdownTab.category;
                      return HomeBreakdownListPage(tab: tab);
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 1 — Reports (full analytics UI)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/reports',
                name: 'reports_full',
                builder: (context, state) => const FullReportsPage(),
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
