# FINDINGS: Untyped Empty Map Fallback — `return {};` / `return const {};` (CONFIRMED #1)

**Status:** 🔍 VERIFIED — Ready for fix

---

## Root Cause

On Flutter Web (Dart Dev Compiler / DDC), an untyped empty map literal `{}` compiles to `ImmutableMap<dynamic, dynamic>` (or `LinkedMap<dynamic, dynamic>` at runtime), **not** `Map<String, dynamic>`.

When a provider returns `{}` and the return type is declared as `Map<String, dynamic>`, the type checker at runtime (DDC) fails:
```
TypeError: Instance of 'LinkedMap<dynamic, dynamic>' is not a subtype of type 'Map<String, dynamic>?'
```

This causes:
- Provider state to fail silently (returns error instead of empty map)
- Downstream UI sees stale data or loading state
- "Saved but UI didn't update" reports (the patch applies, but provider refetch returns error → UI never paints fresh data)

---

## Confirmed Hits: 19 Files, 70 Total Occurrences

All 19 files have return type `Map<String, dynamic>` (or `Map<String, dynamic>?`), so the fix is mechanically safe: `{}` → `<String, dynamic>{}`, `const {}` → `const <String, dynamic>{}`.

### Files with `return {};` (14 files)

| File | Line(s) | Context / Return Type |
|------|---------|----------------------|
| `lib/core/providers/stock_list_providers.dart` | 436, 439, 599-605, 849, 1036, 1055, 1076, 1121, 1173, 1294, 1304 | `FutureProvider<Map<String, dynamic>>`, `StateProvider<Map<String, Map<...>>>` |
| `lib/core/providers/reports_bi_providers.dart` | 17, 34, 44 | `FutureProvider<Map<String, dynamic>>` |
| `lib/core/providers/operations_providers.dart` | 28, 31, 43, 59, 88, 101 | `FutureProvider<Map<String, dynamic>>` |
| `lib/core/providers/catalog_providers.dart` | 79, 96, 107, 143, 170, 182, 202 | `FutureProvider<Map<String, dynamic>>` |
| `lib/features/catalog/presentation/catalog_duplicates_page.dart` | 13 | `FutureProvider<Map<String, dynamic>>` |
| `lib/features/operations/presentation/owner_tasks_page.dart` | 13 | `FutureProvider<Map<String, dynamic>>` |
| `lib/core/api/hexa_api_purchase.dart` | 154, 173, 187, 201, 228, 243, 258, 275, 285, 309, 337, 348, 373, 391, 410, 421, 453, 471, 509, 526, 543, 561, 574, 585 | `Future<Map<String, dynamic>>` / `Future<Map<String, dynamic>?>` |
| `lib/core/api/hexa_api_contacts.dart` | 78, 97, 107, 161, 206, 253, 271, 288, 302 | `Future<Map<String, dynamic>>` / `Future<Map<String, dynamic>?>` |
| `lib/core/providers/stock_detail_providers.dart` | 70, 75, 132, 143, 159, 177, 187 | `FutureProvider<Map<String, dynamic>>` / `FutureProvider<List<...>>` / `StateProvider.autoDispose.family<Map<String, dynamic>, String>` |
| `lib/features/settings/users/user_profile_providers.dart` | 9, 21, 34, 47, 58, 69, 82 | `FutureProvider<Map<String, dynamic>>` / `FutureProvider<List<...>>` |
| `lib/core/providers/stock_audit_providers.dart` | 17, 20 | `FutureProvider<Map<String, dynamic>>` |
| `lib/core/providers/low_stock_providers.dart` | 85, 104, 117, 140, 170, 187 | `FutureProvider<Map<String, dynamic>>` |
| `lib/core/providers/full_reports_insights_providers.dart` | 11, 18, 19 | `FutureProvider<Map<String, dynamic>>` / `FutureProvider<Map<String, dynamic>?>` |
| `lib/core/providers/delivery_pipeline_provider.dart` | 17, 22 | `FutureProvider<Map<String, dynamic>>` |

### Files with `return const {};` (5 files)

| File | Line(s) | Context / Return Type |
|------|---------|----------------------|
| `lib/core/providers/stock_list_providers.dart` | 236, 464, 599 | `FutureProvider<Map<String, dynamic>>` |
| `lib/features/barcode/presentation/bulk_barcode_print_page.dart` | 119, 123 | `StateProvider<Map<String, Map<...>>>` initializer |
| `lib/features/stock/stock_list_row_patch.dart` | 56, 124 | Helper return type `Map<String, dynamic>` |
| `lib/core/api/hexa_api_reports.dart` | 14, 29, 47, 85, 98, 111, 126, 139, 158, 173, 187, 217, 232, 265, 279, 293, 307, 325, 339, 364, 380 | `Future<Map<String, dynamic>>` / `Future<Map<String, dynamic>?>` |
| `lib/core/providers/realtime_events_provider.dart` | 31, 42, 52, 60 | `RealtimeInvalidationSignal` field defaults |

---

## Fix Plan

Mechanical find/replace in each file:

```dart
// Before
return {};

// After
return <String, dynamic>{};
```

```dart
// Before
return const {};

// After
return const <String, dynamic>{};
```

---

## Verification

After fix:
1. Run `flutter analyze` — should pass with no new errors
2. Run unit tests — should pass
3. Manual test: save stock qty on web → verify `[STOCK_STORM]` logs show one refetch and UI updates instantly