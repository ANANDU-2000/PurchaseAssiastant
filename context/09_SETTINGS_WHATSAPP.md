# SPEC 09 — SETTINGS & WHATSAPP AUTO-REPORT
> Reference: `@.cursor/00_AGENT_RULES.md` first

---

## STATUS
| Task | Status |
|------|--------|
| WhatsApp report MVP sheet | ✅ Done |
| Scheduled WhatsApp report (daily/weekly/monthly) | ✅ Done |
| Settings — remove app logo/name | ⚠️ Not targeted (no app logo/name section found) |
| Settings — remove "Get started" after complete | ✅ Done (not present) |
| Settings — clean layout | ⚠️ Implemented (WhatsApp + notifications consolidated) |
| Date field → iOS native `CupertinoDatePicker` | ✅ Done |

---

## FILES TO EDIT
```
flutter_app/lib/features/settings/presentation/settings_page.dart
flutter_app/lib/features/reports/presentation/reports_whatsapp_sheet.dart
flutter_app/lib/features/reports/reports_prefs.dart
flutter_app/lib/core/notifications/local_notifications_service.dart
```

---

## WHAT TO DO

### ❌ TASK 09-A: Settings page cleanup

**File:** `settings_page.dart`

**REMOVE from settings:**
- App logo image widget (if any)
- App name text "PurchaseAssistant" or similar branding section
- "Get started" guide section (check if `onboardingComplete` flag — hide if true)
- Any debug/developer options section

**KEEP:**
- Profile (name, business name)
- Notifications toggle
- WhatsApp reports section (see 09-B)
- Appearance (theme)
- About / version

---

### ❌ TASK 09-B: WhatsApp auto-report scheduling

**File:** `reports_whatsapp_sheet.dart` + `reports_prefs.dart`

Currently the sheet shows a "WhatsApp report (MVP)" with manual send only.

**Add scheduled report feature:**

```dart
// In reports_prefs.dart, add:
class ReportsPrefs {
  static const _schedEnabledKey = 'wa_report_schedule_enabled';
  static const _schedTypeKey = 'wa_report_schedule_type';   // daily|weekly|monthly
  static const _schedTimeKey = 'wa_report_schedule_time';   // HH:mm string
  static const _schedPhoneKey = 'wa_report_phone';

  static Future<bool> getScheduleEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_schedEnabledKey) ?? false;
  }

  static Future<void> setScheduleEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_schedEnabledKey, v);
  }

  static Future<String> getScheduleType() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_schedTypeKey) ?? 'weekly';
  }

  static Future<void> setScheduleType(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_schedTypeKey, v);
  }
  // Similar for time and phone
}
```

**Schedule using `local_notifications_service.dart`:**

```dart
// In WhatsApp report settings, when toggle enabled:
Future<void> _scheduleReportNotification() async {
  final type = await ReportsPrefs.getScheduleType();
  final timeStr = await ReportsPrefs.getScheduleTime(); // e.g. "08:00"
  final timeParts = timeStr.split(':');
  final hour = int.tryParse(timeParts[0]) ?? 8;
  final minute = int.tryParse(timeParts.length > 1 ? timeParts[1] : '0') ?? 0;

  // Schedule a daily notification at the set time
  // The notification, when tapped, triggers the WhatsApp report send
  await LocalNotificationsService.scheduleDaily(
    id: 9001,
    title: 'WhatsApp Report',
    body: 'Tap to send today\'s purchase report via WhatsApp',
    hour: hour,
    minute: minute,
    payload: 'whatsapp_report',
  );
}
```

**Handle notification tap in app router:**
```dart
// When payload == 'whatsapp_report':
// Generate report PDF → open WhatsApp deeplink
await _sendWhatsAppReport();

Future<void> _sendWhatsAppReport() async {
  final phone = await ReportsPrefs.getSchedulePhone();
  // Generate report as text summary
  final summary = await _buildReportSummary();
  final msg = Uri.encodeComponent(summary);
  final url = 'https://wa.me/$phone?text=$msg';
  if (await canLaunchUrl(Uri.parse(url))) {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
```

**UI in settings:**
```
WhatsApp Reports
─────────────────────────────────────────
Auto-report           [Toggle ON/OFF]
Schedule              [Daily ▾]
Time                  [08:00 AM]
Send to               [+91 94470...]
─────────────────────────────────────────
[Send test report now]
```

---

### ❌ TASK 09-C: iOS date picker in wizard

**File:** `purchase_entry_wizard_v2.dart` (or wherever date is picked for purchase)

Replace any `showDatePicker` (Material) with `showCupertinoModalPopup` + `CupertinoDatePicker`:

```dart
Future<void> _pickDate(BuildContext context) async {
  DateTime? picked;
  await showCupertinoModalPopup(
    context: context,
    builder: (_) => Container(
      height: 300,
      color: CupertinoColors.systemBackground.resolveFrom(context),
      child: Column(
        children: [
          // Toolbar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CupertinoButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.pop(context),
              ),
              CupertinoButton(
                child: const Text('Done'),
                onPressed: () {
                  Navigator.pop(context);
                  if (picked != null) _onDateSelected(picked!);
                },
              ),
            ],
          ),
          Expanded(
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.date,
              initialDateTime: _selectedDate ?? DateTime.now(),
              maximumDate: DateTime.now().add(const Duration(days: 1)),
              onDateTimeChanged: (d) => picked = d,
            ),
          ),
        ],
      ),
    ),
  );
}
```

---

## VALIDATION
- [ ] Settings page has no app logo or "PurchaseAssistant" header
- [ ] "Get started" not shown if user has purchases
- [ ] WhatsApp auto-report toggle saves preference
- [ ] Scheduled notification fires at set time
- [ ] Tapping notification opens WhatsApp with report text
- [ ] Date picker uses iOS native wheel picker (not Material calendar)
