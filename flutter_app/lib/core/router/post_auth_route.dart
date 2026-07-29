import 'package:shared_preferences/shared_preferences.dart';

import '../models/session.dart';
import 'intended_route.dart';

bool sessionIsStaff(Session session) =>
    session.primaryBusiness.role.toLowerCase() == 'staff';

/// Owner, admin, and manager may see purchase rates, totals, and margins.
bool sessionCanSeeFinancials(Session session) => !sessionIsStaff(session);

/// Owner / manager / platform super-admin may view the user list.
bool sessionCanManageUsers(Session session) {
  final r = session.primaryBusiness.role.toLowerCase();
  return r == 'owner' || r == 'admin' || r == 'manager' || session.isSuperAdmin;
}

/// Owner, admin, or platform super-admin may create staff logins.
bool sessionCanCreateUsers(Session session) {
  final r = session.primaryBusiness.role.toLowerCase();
  return r == 'owner' || r == 'admin' || session.isSuperAdmin;
}

bool sessionCanAdminUsers(Session session) {
  final r = session.primaryBusiness.role.toLowerCase();
  return r == 'owner' || r == 'admin' || session.isSuperAdmin;
}

/// Main tab shell after sign-in / splash (owner vs staff).
String authenticatedHomePath(Session session) =>
    sessionIsStaff(session) ? '/staff/home' : '/home';

/// Prefer a stored deep link after login / session restore; otherwise home.
///
/// Staff restore must stay aligned with router allowlist (`_isStaffAllowedRoute`):
/// keep `/reports`, `/purchase/new|edit|detail`, `/settings`, etc. Only remap
/// owner shell tabs that staff must not enter.
String resolvePostAuthPath(Session session, SharedPreferences prefs) {
  final intended = takeIntendedProtectedRoute(prefs);
  if (intended == null) return authenticatedHomePath(session);
  final pathOnly = intended.split('?').first;
  if (sessionIsStaff(session)) {
    if (pathOnly == '/home' || pathOnly.startsWith('/home/')) {
      return '/staff/home';
    }
    if (pathOnly == '/stock') return '/staff/stock';
    if (pathOnly == '/search') return '/staff/search';
    // Owner purchase history list — staff uses deliveries hub.
    if (pathOnly == '/purchase') return '/staff/deliveries';
    // Allowed overlays (reports drill, purchase detail/edit/new, settings…).
    if (pathOnly == '/purchase/new' ||
        pathOnly.startsWith('/purchase/edit/') ||
        pathOnly.startsWith('/purchase/detail/') ||
        pathOnly == '/reports' ||
        pathOnly.startsWith('/reports/') ||
        pathOnly == '/settings' ||
        pathOnly.startsWith('/settings/') ||
        pathOnly == '/notifications' ||
        pathOnly.startsWith('/barcode/') ||
        pathOnly.startsWith('/staff') ||
        pathOnly.startsWith('/operations/') ||
        pathOnly.startsWith('/catalog/item/') ||
        pathOnly == '/catalog/quick-add' ||
        pathOnly == '/catalog/quick-add-from-scan' ||
        pathOnly == '/catalog/missing-codes' ||
        pathOnly == '/catalog/taxonomy') {
      return intended;
    }
    // Remaining purchase/* that is not new/edit/detail → deliveries.
    if (pathOnly.startsWith('/purchase')) return '/staff/deliveries';
    return authenticatedHomePath(session);
  }
  if (pathOnly.startsWith('/staff')) {
    return '/home';
  }
  return intended;
}
