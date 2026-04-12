import { useCallback, useEffect, useState } from 'react'
import { adminGet, adminPatch, userSafePageError } from '../../lib/api'

type Flags = {
  enable_ai: boolean
  enable_ocr: boolean
  enable_voice: boolean
  enable_realtime: boolean
  whatsapp_bot: boolean
}

const LABELS: { key: keyof Flags; label: string; hint: string }[] = [
  { key: 'whatsapp_bot', label: 'WhatsApp assistant', hint: 'Automated replies on WhatsApp' },
  { key: 'enable_ai', label: 'AI assist', hint: 'Smarter purchase entry and chat' },
  { key: 'enable_voice', label: 'Voice', hint: 'Voice notes and transcription' },
  { key: 'enable_ocr', label: 'Scan bills', hint: 'Read text from photos' },
  { key: 'enable_realtime', label: 'Live updates', hint: 'Fresher activity in the dashboard' },
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
        if (!cancelled) setErr(userSafePageError(e))
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
      setErr(userSafePageError(e))
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
