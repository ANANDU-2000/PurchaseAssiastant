# FINDINGS: Barcode Generation/Rebuild Very Slow (Issue #4)

**Status:** Root cause confirmed in code. Ready for fix implementation after approval.

---

## Confirmed Root Cause

### 1. `generateBatch` (Thermal Path) — Main Thread Blocking

**File:** `flutter_app/lib/features/barcode/services/barcode_pdf_service.dart`  
**Method:** `generateBatch` (lines 264–351)

This method:
- Runs entirely on the **main UI isolate** (no `compute()` / `Isolate.run`)
- Iterates `for (final data in expanded) { doc.addPage(...) }` — one label at a time
- Each label's PDF page is drawn **synchronously** on the UI thread
- This blocks the app UI while generating — "one by one, very slow" as reported

**Contrast with `generateBatchA4Dense` (lines 358–420):**
- Uses `compute(_barcodeA4DenseFromPayload, payload)` (line 400)
- `_barcodeA4DenseFromPayload` is a **top-level function** (lines 1323–1325) — isolate-safe
- Payload is pure data (JSON-serializable `Map<String, dynamic>`) — no `BuildContext`, no closures
- Comment on line 354: *"Runs off the UI thread on VM via Isolate.run."*

### 2. Sequential Chunk Processing in Controller

**File:** `flutter_app/lib/features/barcode/presentation/bulk_barcode_print_controller.dart`  
**Method:** `generateBulkPdfParts` (lines 314–438)

- **A4 dense path** (lines 369–388): `for (final chunk in chunks) { await _generatePdfForLabelChunk(...) }` — sequential
- **Thermal path** (lines 400–418): same sequential loop

For the already-offloaded A4 path, this serializes isolate hops (smaller win). For the thermal path, it **compounds** the main-thread blocking above.

---

## Call Chain Confirmation

### Thermal Roll Path (≤25 labels — default for routine small batches)

```
User taps "Print" (thermal)
  → bulk_barcode_print_controller.generateBulkPdfParts()
    → chunkExpandedLabelsForPdfFiles()  // splits into chunks
    → for each chunk:
        → _generatePdfForLabelChunk(denseA4: false)
          → BarcodePdfService.generateBatch()  // ← MAIN THREAD, NO ISOLATE
```

### A4 Dense Path (larger batches)

```
User taps "Print" (A4)
  → bulk_barcode_print_controller.generateBulkPdfParts()
    → chunkExpandedLabelsForPdfFiles()
    → for each chunk:
        → _generatePdfForLabelChunk(denseA4: true)
          → BarcodePdfService.generateBatchA4Dense()
            → compute(_barcodeA4DenseFromPayload, payload)  // ← OFFLOADED TO ISOLATE
```

---

## Proposed Fix: Move `generateBatch` to `compute()` / `Isolate.run`

### Pattern to Follow (from `generateBatchA4Dense`)

1. Create a **top-level function** (library-level, not a static method) that takes a serializable payload
2. Move the PDF building logic into that function
3. Call it via `compute(topLevelFunction, payload)` on VM, or direct `await` on web

### Obstacles to Check

| Potential Issue | `generateBatchA4Dense` Approach | `generateBatch` Current State |
|-----------------|----------------------------------|-------------------------------|
| `BuildContext` / `MediaQuery` | Not used — payload is pure data | **Not used** — pure data only ✓ |
| Closures over non-isolate-safe objects | Avoided — payload passed explicitly | **None apparent** ✓ |
| `AppConfig.webAppBaseUrl` (static) | Used in `_symbologyValue` → called from payload builder | Used same way — static access is fine ✓ |
| `pdf` package (`pw.Document`) | Works in isolate (tested) | Same package — should work ✓ |

**Verdict:** No obvious obstacle. `generateBatch` appears to be pure data-in, bytes-out — same as `generateBatchA4Dense`.

### Proposed Code Structure

```dart
// In barcode_pdf_service.dart — add top-level function (like _barcodeA4DenseFromPayload)
Future<Uint8List> _barcodeBatchFromPayload(Map<String, dynamic> payload) {
  return BarcodePdfService._buildBatchPdf(payload);
}

// Inside BarcodePdfService — extract the build logic to a static method
static Future<Uint8List> _buildBatchPdf(Map<String, dynamic> payload) {
  // ... existing generateBatch body, reading from payload instead of params
}

// Public generateBatch becomes:
static Future<Uint8List> generateBatch({...}) async {
  final payload = {...}; // serialize all params
  if (kIsWeb) {
    await Future<void>.delayed(Duration.zero);
    return await _barcodeBatchFromPayload(payload);
  }
  return await compute(_barcodeBatchFromPayload, payload);
}
```

---

## Secondary Optimization: Parallel Chunk Generation

**File:** `bulk_barcode_print_controller.dart`  
**Current:** Sequential `for (chunk in chunks) { await ... }` (lines 369–388, 400–418)

**Proposed:** Bounded parallel using existing `maxParallel = 3` pattern (line 45 in same file)

```dart
// Instead of sequential for-loop:
final results = await Future.wait(
  chunks.map((chunk) => _generatePdfForLabelChunk(...)).toList(),
);
// Or bounded parallel in waves of 3 (matching fetchBulkLabels pattern)
```

**Tradeoff to Flag:**
- ✅ **Pro:** 2–3× faster PDF generation for multi-chunk batches
- ⚠️ **Risk:** On low-end devices, 3 concurrent isolates × PDF memory = potential OOM
- 💡 **Recommendation:** Start with sequential for thermal (small batches ≤25, usually 1 chunk). For A4 dense (larger batches), consider bounded parallel **only if** chunk count > 1 and device memory allows. Add a device-memory check or make it configurable.

---

## Verification Required Before Merge

1. **Byte-identical output:** Compare PDF bytes before/after for same input — barcode scannability must not regress
2. **Device test:** Print thermal roll on physical device — confirm no UI freeze during generation
3. **A4 dense unchanged:** Ensure `generateBatchA4Dense` behavior is identical (it already uses isolate)
4. **Web build:** Confirm `kIsWeb` path still works (direct await, no compute)

---

## Next Steps

**Waiting for approval to implement:**
1. ✅ Findings documented — this file
2. ⏳ **Approve** → implement `compute()` offload for `generateBatch`
3. ⏳ Test on device (thermal + A4)
4. ⏳ Decide on parallel chunk generation (separate decision)

**Do not edit** `bulk_barcode_print_controller.dart` chunk loop yet — isolate offload is the primary fix; parallel chunks are a follow-up optimization.