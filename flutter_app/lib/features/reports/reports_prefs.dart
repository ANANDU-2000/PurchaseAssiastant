import 'package:shared_preferences/shared_preferences.dart';

/// Local-only prefs for MVP WhatsApp report reminders (no server).
class ReportsPrefs {
  static const phoneKey = 'reports_whatsapp_phone_e164';
  static const freqKey = 'reports_whatsapp_freq';

  static Future<String?> getPhone() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(phoneKey);
  }

  static Future<void> setPhone(String? v) async {
    final sp = await SharedPreferences.getInstance();
    if (v == null || v.trim().isEmpty) {
      await sp.remove(phoneKey);
    } else {
      await sp.setString(phoneKey, v.trim());
    }
  }

  /// daily | weekly | monthly
  static Future<String> getFrequency() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(freqKey) ?? 'weekly';
  }

  static Future<void> setFrequency(String v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(freqKey, v);
  }
}
