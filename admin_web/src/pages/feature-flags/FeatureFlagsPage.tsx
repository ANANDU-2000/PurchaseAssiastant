import { useCallback, useEffect, useState } from 'react'
import { AdminErrorBanner } from '../../components/AdminErrorBanner'
import { adminGet, adminPatch, devErrorDetail, userSafePageError } from '../../lib/api'

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

function labelForKey(key: keyof Flags): string {
  return LABELS.find((l) => l.key === key)?.label ?? key
}

export default function FeatureFlagsPage() {
  const [data, setData] = useState<Flags | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [errDev, setErrDev] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [busy, setBusy] = useState<keyof Flags | null>(null)

  const load = useCallback(async () => {
    const f = await adminGet<Flags>('/v1/admin/feature-flags')
    setData(f)
  }, [])

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      setLoading(true)
      setErr(null)
      setErrDev(null)
      try {
        await load()
      } catch (e: unknown) {
        if (!cancelled) {
          setErr(userSafePageError(e))
          setErrDev(devErrorDetail(e))
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [load])

  async function refresh() {
    setRefreshing(true)
    setErr(null)
    setErrDev(null)
    try {
      await load()
    } catch (e: unknown) {
      setErr(userSafePageError(e))
      setErrDev(devErrorDetail(e))
    } finally {
      setRefreshing(false)
    }
  }

  async function toggle(key: keyof Flags, value: boolean) {
    if (!data) return
    setBusy(key)
    setErr(null)
    setErrDev(null)
    try {
      await adminPatch('/v1/admin/feature-flags', { [key]: value })
      await load()
    } catch (e: unknown) {
      setErr(userSafePageError(e))
      setErrDev(devErrorDetail(e))
    } finally {
      setBusy(null)
    }
  }

  return (
    <section className="admin-data-page feature-flags-page">
      <div className="admin-page-head">
        <h1>Feature flags</h1>
        <button type="button" className="pk-btn pk-btn--primary" disabled={loading || refreshing} onClick={() => void refresh()}>
          {refreshing ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>
      <p className="admin-data-intro">
        Values are stored in the database (<code>feature_flags</code>) and override deployment defaults from environment variables.
      </p>

      {err && <AdminErrorBanner message={err} devDetail={errDev} />}

      {loading && <p className="admin-data-empty">Loading…</p>}

      {data && !loading && (
        <>
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
          {busy && <p className="admin-data-note">Updating {labelForKey(busy)}…</p>}
        </>
      )}
    </section>
  )
}
