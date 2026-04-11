import { useEffect, useState } from 'react'
import { adminGet } from '../../lib/api'

type Flags = {
  enable_ai: boolean
  enable_ocr: boolean
  enable_voice: boolean
  enable_realtime: boolean
}

export default function FeatureFlagsPage() {
  const [data, setData] = useState<Flags | null>(null)
  const [err, setErr] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const f = await adminGet<Flags>('/v1/admin/feature-flags')
        if (!cancelled) setData(f)
      } catch (e: unknown) {
        if (!cancelled) setErr(e instanceof Error ? e.message : String(e))
      }
    })()
    return () => {
      cancelled = true
    }
  }, [])

  return (
    <section>
      <h1>Feature flags</h1>
      <p>Global deployment flags from the backend (per-tenant overrides require DB wiring).</p>
      {err && <p style={{ color: 'crimson' }}>{err}</p>}
      {data && (
        <ul>
          <li>ENABLE_AI: {String(data.enable_ai)}</li>
          <li>ENABLE_OCR: {String(data.enable_ocr)}</li>
          <li>ENABLE_VOICE: {String(data.enable_voice)}</li>
          <li>ENABLE_REALTIME: {String(data.enable_realtime)}</li>
        </ul>
      )}
    </section>
  )
}
