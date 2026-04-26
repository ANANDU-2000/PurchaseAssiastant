/// Fixed maintenance payment — never user-editable in UI.
abstract class MaintenancePaymentConstants {
  MaintenancePaymentConstants._();

  static const int amountInr = 2500;

  /// UPI VPA (display + link).
  static const String upiId = 'krishnaanamdhu12-5@okicici';

  static const String merchantName = 'Harisree Tech';

  /// Canonical deep link (amount fixed in query).
  static const String upiUri =
      'upi://pay?pa=krishnaanamdhu12-5@okicici&pn=Harisree%20Tech&am=2500&cu=INR&tn=Monthly%20Maintenance';

  static const String recordsPrefsKey = 'maintenance_records_v1';
  static const String remindersEnabledPrefsKey =
      'pref_maintenance_reminders_enabled';
}
