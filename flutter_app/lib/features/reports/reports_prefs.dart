import 'package:shared_preferences/shared_preferences.dart';

/// Local-only prefs for MVP WhatsApp report reminders (no server).
class ReportsPrefs {
  static const phoneKey = 'reports_whatsapp_phone_e164';
  static const freqKey = 'reports_whatsapp_freq';

  static const _schedEnabledKey = 'wa_report_schedule_enabled';
  static const _schedTypeKey = 'wa_report_schedule_type'; // daily|weekly|monthly
  static const _schedTimeKey = 'wa_report_schedule_time'; // HH:mm (24h)
  static const _schedPhoneKey = 'wa_report_phone';

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

  static Future<bool> getScheduleEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_schedEnabledKey) ?? false;
  }

  static Future<void> setScheduleEnabled(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_schedEnabledKey, v);
  }

  /// daily | weekly | monthly
  static Future<String> getScheduleType() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_schedTypeKey) ?? 'weekly';
  }

  static Future<void> setScheduleType(String v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_schedTypeKey, v);
  }

  /// HH:mm in 24h format (local time)
  static Future<String> getScheduleTime() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_schedTimeKey) ?? '08:00';
  }

  static Future<void> setScheduleTime(String v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_schedTimeKey, v);
  }

  static Future<String> getSchedulePhone() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_schedPhoneKey) ?? '';
  }

  static Future<void> setSchedulePhone(String v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_schedPhoneKey, v.trim());
  }
}
