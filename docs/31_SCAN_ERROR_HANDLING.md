# Scan Error Handling

## UX states
- **Empty**: “Upload a bill photo to begin”
- **Processing**: staged status with spinner
- **Success**: preview table
- **Error**: actionable guidance + retry

## Common errors
- Blurry / low light → ask retake or crop
- Multi-page long bills → multi-photo mode (future)
- OCR empty → retry + fallback
- LLM malformed → retry + failover
- Network timeout → show retry, keep selected image

