# 14 — WHATSAPP ASSISTANT & SETTINGS BUGS

> `@.cursor/00_STATUS.md` first

---

## STATUS


| Task                                                    | Status                                   |
| ------------------------------------------------------- | ---------------------------------------- |
| **BUG: "create broker" shows "Type: Supplier" preview** | ✅ Fixed (LLM overrides + preview text)   |
| **BUG: "Save WhatsApp schedule" button does nothing**   | ✅ Fixed (permission + feedback)          |
| **BUG: "Send test report now" does nothing visually**   | ✅ Fixed (loading + errors)               |
| WhatsApp assistant purchase creation                    | ✅ Works                                  |
| WhatsApp assistant broker create (backend)              | ✅ Works (text format)                    |
| Alerts & Reminders page empty                           | ✅ Fixed (filter empty state + Show all)  |
| Entity preview card for supplier                        | ✅ Works                                  |
| Entity preview card for broker                          | ✅ Fixed (backend `Type:` / `Name:` lines) |
| Registered business name not saving                     | ✅ Fixed (`name` on branding patch + UI)  |


---

## FILES TO EDIT

```
flutter_app/lib/features/assistant/presentation/widgets/entity_preview_card.dart
flutter_app/lib/features/settings/presentation/settings_page.dart
flutter_app/lib/features/settings/presentation/business_profile_page.dart
flutter_app/lib/features/notifications/presentation/notifications_page.dart
flutter_app/lib/core/api/hexa_api.dart
flutter_app/lib/core/notifications/local_notifications_service.dart
backend/app/routers/me.py
backend/app/services/whatsapp_transaction_engine.py
backend/app/services/llm_intent.py
```

---

## BUG C3: "create broker" shows "Type: Supplier" preview

**Root cause — TWO separate issues:**

**Issue 1: LLM misclassifies "create broker name raju" as `create_supplier`**

In `llm_intent.py`, the LLM system prompt says:

```
"create supplier ravi" → create_supplier
```

When user types "cretae broker name raju" (typos), LLM may map to `create_supplier` 
because the intent classification isn't robust to typos.

**Fix in `backend/app/services/llm_intent.py`** — add to the system prompt examples:

```python
# In the few-shot examples section, add:
"""
- "create broker raju" → create_broker
- "cretae broker name raju" → create_broker  (typos ok)
- "add broker edison" → create_broker
- "new broker rice and rice" → create_broker
- "add supplier surag" → create_supplier
- "new supplier vk traders" → create_supplier
IMPORTANT: "broker" keyword ALWAYS → create_broker, never create_supplier
"supplier" keyword ALWAYS → create_supplier, never create_broker
If both present: first one wins.
"""
```

**Issue 2: Flutter preview card always shows "Supplier preview" title**

**File:** `entity_preview_card.dart` line ~113

```dart
// CURRENT (wrong):
'${parse.kindLabel} preview',   // kindLabel = "Supplier" always

// ROOT CAUSE: parseEntityPreviewFromReply reads "Type: Supplier" from backend
// but for broker creation, backend sends:
// "*New broker*\nRaju\nCommission: —\n\nReply *YES* to add."
// which has NO "Type:" key → parseEntityPreviewFromReply returns null
// → falls back to generic "Supplier preview"
```

**Fix in `backend/app/services/whatsapp_transaction_engine.py`** — 
change broker preview text to key:value format:

```python
# FIND (around line 851):
await _wa(
    f"*New broker*\\n{name}\\nCommission: {cflat if cflat is not None else '—'}\\n\\nReply *YES* to add.",
    scene="preview",
)

# REPLACE WITH:
await _wa(
    f"Preview (not saved):\\nType: Broker\\nName: {name}\\nCommission: {cflat if cflat is not None else '—'}\\n\\nReply YES to save, NO to cancel.",
    scene="preview",
)
```

**Do the same for `create_supplier` and `create_item` previews** — ensure they all send:

```
Preview (not saved):
Type: Supplier   ← or Broker, or Item
Name: X
...
Reply YES to save, NO to cancel.
```

This way `parseEntityPreviewFromReply` correctly sets `kindLabel = "Broker"` or `"Supplier"`.

---

## BUG C4: WhatsApp "Save schedule" + "Send test" not working

**File:** `flutter_app/lib/features/settings/presentation/settings_page.dart`

### Issue A: Save schedule button — `_applyWhatsAppSchedule()`

Find `_applyWhatsAppSchedule()`. It likely saves to SharedPreferences but:

1. May not show any feedback to user
2. Local notification scheduling may fail silently on iOS (needs permission)

**Fix:**

```dart
Future<void> _applyWhatsAppSchedule() async {
  setState(() => _waSchedBusy = true);
  try {
    // Save prefs
    await ReportsPrefs.setScheduleEnabled(_waSchedEnabled);
    await ReportsPrefs.setScheduleType(_waSchedType);
    await ReportsPrefs.setScheduleTime(_waSchedTimeStr);
    await ReportsPrefs.setSchedulePhone(_waPhoneCtrl.text.trim());
    
    if (_waSchedEnabled) {
      // Request notification permission first (iOS requires this)
      final granted = await LocalNotificationsService.requestPermission();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please allow notifications in Settings to enable auto-reports'),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
      
      // Schedule the notification
      await LocalNotificationsService.scheduleWhatsAppReport(
        type: _waSchedType,
        timeStr: _waSchedTimeStr,
      );
    } else {
      await LocalNotificationsService.cancelWhatsAppReport();
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ WhatsApp report schedule saved'),
          backgroundColor: Color(0xFF1B6B5A),
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
      );
    }
  } finally {
    if (mounted) setState(() => _waSchedBusy = false);
  }
}
```

### Issue B: Send test report — no visual feedback

Find `_sendTestWhatsAppReportNow()`. It opens WhatsApp but shows no loading state.

**Fix — add loading state:**

```dart
bool _waSendingTest = false;

// Wrap the existing function:
Future<void> _sendTestWhatsAppReportNow() async {
  if (_waSendingTest) return;
  setState(() => _waSendingTest = true);
  try {
    // [existing logic to build report text]
    // ...
    final uri = Uri.parse('https://wa.me/$phone?text=$msg');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp not installed or number invalid')),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  } finally {
    if (mounted) setState(() => _waSendingTest = false);
  }
}

// In button widget:
ElevatedButton(
  onPressed: _waSendingTest ? null : () => unawaited(_sendTestWhatsAppReportNow()),
  child: _waSendingTest
      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
      : const Text('Send test report now'),
),
```

---

## BUG: Workspace name field not saving

**File:** `settings_page.dart`

The Business profile "Registered business name" field appears focused but changes don't save.

**Find `_saveBranding()` or similar.** Check if:

1. It awaits the API call correctly
2. It shows success/error feedback
3. The text field controller is properly initialised from current business name

**Fix:**

```dart
Future<void> _saveBusinessProfile() async {
  final name = _businessNameCtrl.text.trim();
  if (name.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Business name cannot be empty')),
    );
    return;
  }
  setState(() => _brandingSaving = true);
  try {
    await ref.read(businessProfileProvider.notifier).updateProfile(
      name: name,
      pdfTitle: _pdfTitleCtrl.text.trim(),
      gstin: _gstinCtrl.text.trim(),
      phone: _bizPhoneCtrl.text.trim(),
      email: _bizEmailCtrl.text.trim(),
      address: _bizAddressCtrl.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Business profile saved'), backgroundColor: Color(0xFF1B6B5A)),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
      );
    }
  } finally {
    if (mounted) setState(() => _brandingSaving = false);
  }
}
```

---

## VALIDATION

- Type "create broker name raju" → preview shows "Broker preview" not "Supplier preview"
- Type "add broker edison" → preview shows "Broker preview", tapping Save creates broker
- "Save WhatsApp schedule" → shows spinner, then "✅ Schedule saved" snackbar
- "Send test report now" → shows spinner, then opens WhatsApp
- Business name field → edit → save → shows success toast → name persists on reopen

