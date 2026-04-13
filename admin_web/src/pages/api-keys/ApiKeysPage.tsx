import { useCallback, useEffect, useState } from 'react'
import { AdminErrorBanner } from '../../components/AdminErrorBanner'
import { adminGet, adminPut, devErrorDetail, userSafePageError } from '../../lib/api'

type FieldMeta = {
  masked: string | null
  source: string
  has_database_value: boolean
  field: string
}

type PlatformIntegrationResponse = {
  effective: {
    openai_configured: boolean
    dialog360_configured: boolean
    razorpay_configured: boolean
    razorpay_mode: string
  }
  fields: Record<string, FieldMeta>
  note: string
}

const GROUPS: { title: string; hint?: string; keys: { key: string; label: string }[] }[] = [
  {
    title: 'AI providers',
    hint: 'Keys are stored in the database and override server environment for this deployment.',
    keys: [
      { key: 'openai_api_key', label: 'OpenAI' },
      { key: 'google_ai_api_key', label: 'Google AI (Gemini)' },
      { key: 'groq_api_key', label: 'Groq' },
    ],
  },
  {
    title: '360dialog (WhatsApp)',
    keys: [
      { key: 'dialog360_api_key', label: 'API key (D360-API-KEY)' },
      { key: 'dialog360_phone_number_id', label: 'Phone number ID' },
      { key: 'dialog360_base_url', label: 'API base URL' },
      { key: 'dialog360_webhook_secret', label: 'Webhook verify secret' },
    ],
  },
  {
    title: 'Razorpay (billing)',
    keys: [
      { key: 'razorpay_key_id', label: 'Key ID' },
      { key: 'razorpay_key_secret', label: 'Key secret' },
      { key: 'razorpay_webhook_secret', label: 'Webhook secret' },
    ],
  },
]

function sourceBadge(source: string): string {
  if (source === 'database') return 'DB override'
  if (source === 'environment') return 'Environment'
  return 'Not set'
}

export default function ApiKeysPage() {
  const [data, setData] = useState<PlatformIntegrationResponse | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [errDev, setErrDev] = useState<string | null>(null)
  const [ok, setOk] = useState<string | null>(null)
  const [busy, setBusy] = useState<string | null>(null)
  const [reloadBusy, setReloadBusy] = useState(false)
  const [draft, setDraft] = useState<Record<string, string>>({})

  const load = useCallback(async () => {
    const d = await adminGet<PlatformIntegrationResponse>('/v1/admin/platform-integration')
    setData(d)
    setDraft({})
  }, [])

  async function reloadFromServer() {
    setReloadBusy(true)
    setErr(null)
    setErrDev(null)
    setOk(null)
    try {
      await load()
      setOk('Reloaded from server.')
    } catch (e: unknown) {
      setErr(userSafePageError(e))
      setErrDev(devErrorDetail(e))
    } finally {
      setReloadBusy(false)
    }
  }

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        await load()
      } catch (e: unknown) {
        if (!cancelled) {
          setErr(userSafePageError(e))
          setErrDev(devErrorDetail(e))
        }
      }
    })()
    return () => {
      cancelled = true
    }
  }, [load])

  async function saveField(field: string) {
    const v = draft[field]?.trim()
    if (!v) return
    setBusy(field)
    setErr(null)
    setErrDev(null)
    setOk(null)
    try {
      await adminPut('/v1/admin/platform-integration', { [field]: v })
      setOk(`Updated ${field}.`)
      await load()
    } catch (e: unknown) {
      setErr(userSafePageError(e))
      setErrDev(devErrorDetail(e))
    } finally {
      setBusy(null)
    }
  }

  async function clearOverride(field: string) {
    if (
      !window.confirm(
        'Remove the database value for this field? The server will fall back to environment variables if present.',
      )
    ) {
      return
    }
    setBusy(field)
    setErr(null)
    setErrDev(null)
    setOk(null)
    try {
      await adminPut('/v1/admin/platform-integration', { [field]: '' })
      setOk(`Cleared DB override for ${field}.`)
      await load()
    } catch (e: unknown) {
      setErr(userSafePageError(e))
      setErrDev(devErrorDetail(e))
    } finally {
      setBusy(null)
    }
  }

  return (
    <section className="admin-data-page api-keys-page">
      <div className="admin-page-head">
        <h1>Access keys</h1>
        <button
          type="button"
          className="pk-btn pk-btn--primary"
          disabled={reloadBusy || busy !== null}
          onClick={() => void reloadFromServer()}
        >
          {reloadBusy ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>
      <p className="admin-data-intro">
        Override integration secrets in the database (no redeploy). Values are never shown in full — only a short masked
        tail. Paste a new secret and save, or remove the DB override to use <code>.env</code> again.
      </p>

      {!data && !err && <p className="admin-data-empty">Loading…</p>}

      {err && <AdminErrorBanner message={err} devDetail={errDev} />}
      {ok && (
        <p className="pk-banner pk-banner--ok" role="status">
          {ok}
        </p>
      )}

      {data && (
        <>
          <div className="pk-effective">
            <div className="pk-metric">
              <span className="pk-metric-label">OpenAI</span>
              <span className="pk-metric-val">{data.effective.openai_configured ? 'on' : 'off'}</span>
            </div>
            <div className="pk-metric">
              <span className="pk-metric-label">360dialog</span>
              <span className="pk-metric-val">{data.effective.dialog360_configured ? 'on' : 'off'}</span>
            </div>
            <div className="pk-metric">
              <span className="pk-metric-label">Razorpay</span>
              <span className="pk-metric-val">
                {data.effective.razorpay_configured ? data.effective.razorpay_mode : 'off'}
              </span>
            </div>
          </div>
          <p className="admin-data-note admin-data-note--tight">{data.note}</p>

          {GROUPS.map((g) => (
            <div key={g.title} className="pk-group">
              <h2 className="pk-group-title">{g.title}</h2>
              {g.hint && <p className="pk-group-hint">{g.hint}</p>}
              <div className="pk-fields">
                {g.keys.map(({ key, label }) => {
                  const meta = data.fields[key]
                  if (!meta) return null
                  const disabled = busy !== null
                  return (
                    <div key={key} className="pk-field">
                      <div className="pk-field-head">
                        <span className="pk-field-label">{label}</span>
                        <span className={`pk-badge pk-badge--${meta.source}`}>{sourceBadge(meta.source)}</span>
                      </div>
                      <div className="pk-field-meta">
                        Masked: <code>{meta.masked ?? '—'}</code>
                      </div>
                      <input
                        className="pk-input"
                        type="password"
                        autoComplete="off"
                        placeholder="Paste new value to store in DB…"
                        value={draft[key] ?? ''}
                        disabled={disabled}
                        onChange={(e) => setDraft((d) => ({ ...d, [key]: e.target.value }))}
                      />
                      <div className="pk-field-actions">
                        <button
                          type="button"
                          className="pk-btn pk-btn--primary"
                          disabled={disabled || !(draft[key]?.trim())}
                          onClick={() => void saveField(key)}
                        >
                          {busy === key ? 'Saving…' : 'Save'}
                        </button>
                        <button
                          type="button"
                          className="pk-btn"
                          disabled={disabled || !meta.has_database_value}
                          onClick={() => void clearOverride(key)}
                        >
                          Remove DB override
                        </button>
                      </div>
                    </div>
                  )
                })}
              </div>
            </div>
          ))}
        </>
      )}
    </section>
  )
}
