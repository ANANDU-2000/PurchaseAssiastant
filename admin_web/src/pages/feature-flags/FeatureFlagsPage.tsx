import { useCallback, useEffect, useState } from 'react'
import { adminGet, adminPatch } from '../../lib/api'

type Flags = {
  enable_ai: boolean
  enable_ocr: boolean
  enable_voice: boolean
  enable_realtime: boolean
  whatsapp_bot: boolean
}

const LABELS: { key: keyof Flags; label: string; hint: string }[] = [
  { key: 'whatsapp_bot', label: 'WhatsApp bot', hint: 'Inbound automation via 360dialog webhook' },
  { key: 'enable_ai', label: 'AI parsing', hint: 'AI-assisted entry / chat flows' },
  { key: 'enable_voice', label: 'Voice / STT', hint: 'Voice transcription endpoints' },
  { key: 'enable_ocr', label: 'OCR', hint: 'Bill scan / image text' },
  { key: 'enable_realtime', label: 'Realtime (SSE)', hint: 'Live dashboard stream stub' },
]

export default function FeatureFlagsPage() {
  const [data, setData] = useState<Flags | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [busy, setBusy] = useState<string | null>(null)

  const load = useCallback(async () => {
    const f = await adminGet<Flags>('/v1/admin/feature-flags')
    setData(f)
  }, [])

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        await load()
      } catch (e: unknown) {
        if (!cancelled) setErr(e instanceof Error ? e.message : String(e))
      }
    })()
    return () => {
      cancelled = true
    }
  }, [load])

  async function toggle(key: keyof Flags, value: boolean) {
    if (!data) return
    setBusy(key)
    setErr(null)
    try {
      await adminPatch('/v1/admin/feature-flags', { [key]: value })
      await load()
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(null)
    }
  }

  return (
    <section>
      <h1>Feature flags</h1>
      <p style={{ color: '#555', maxWidth: 640 }}>
        Values are stored in the database (<code>feature_flags</code>) and override deployment defaults from environment
        variables.
      </p>
      {err && <p style={{ color: 'crimson' }}>{err}</p>}
      {data && (
        <ul className="ff-list">
          {LABELS.map(({ key, label, hint }) => (
            <li key={key} className="ff-row">
              <label className="ff-toggle">
                <input
                  type="checkbox"
                  checked={data[key]}
                  disabled={busy !== null}
                  onChange={(e) => void toggle(key, e.target.checked)}
                />
                <span className="ff-label">{label}</span>
              </label>
              <span className="ff-hint">{hint}</span>
            </li>
          ))}
        </ul>
      )}
      {busy && <p style={{ fontSize: 13, color: '#64748b' }}>Updating {busy}…</p>}
    </section>
  )
}
