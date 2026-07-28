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
String resolvePostAuthPath(Session session, SharedPreferences prefs) {
  final intended = takeIntendedProtectedRoute(prefs);
  if (intended == null) return authenticatedHomePath(session);
  final pathOnly = intended.split('?').first;
  if (sessionIsStaff(session)) {
    // Staff must not land on owner-only shells after restore.
    if (pathOnly == '/home' || pathOnly.startsWith('/home/')) {
      return '/staff/home';
    }
    if (pathOnly == '/stock') return '/staff/stock';
    if (pathOnly == '/search') return '/staff/search';
    if (pathOnly.startsWith('/reports') ||
        pathOnly.startsWith('/purchase') ||
        pathOnly.startsWith('/settings')) {
      return '/staff/home';
    }
  } else if (pathOnly.startsWith('/staff')) {
    return '/home';
  }
  return intended;
}
