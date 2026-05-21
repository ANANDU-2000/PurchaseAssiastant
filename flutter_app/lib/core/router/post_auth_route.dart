import '../models/session.dart';

bool sessionIsStaff(Session session) =>
    session.primaryBusiness.role.toLowerCase() == 'staff';

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
