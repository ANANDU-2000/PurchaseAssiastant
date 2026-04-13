import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { AdminErrorBanner } from '../../components/AdminErrorBanner'
import { adminGet, devErrorDetail, userSafePageError } from '../../lib/api'

type IntegEntry = { configured?: boolean; provider?: string; base_url?: string }

type Integ = Record<string, IntegEntry>

const ORDER: { key: string; title: string }[] = [
  { key: 'dialog360', title: '360dialog / WhatsApp' },
  { key: 'openai', title: 'OpenAI' },
  { key: 'ocr', title: 'OCR' },
  { key: 'stt', title: 'Speech-to-text' },
  { key: 's3', title: 'Object storage (S3)' },
  { key: 'razorpay', title: 'Razorpay' },
  { key: 'sentry', title: 'Sentry' },
  { key: 'redis', title: 'Redis' },
]

export default function IntegrationsPage() {
  const [data, setData] = useState<Integ | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [errDev, setErrDev] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)

  const load = useCallback(async () => {
    const d = await adminGet<Integ>('/v1/admin/integrations')
    setData(d)
  }, [])

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

  return (
    <section className="integrations-page">
      <div className="integ-head">
        <h1>Integrations</h1>
        <button type="button" className="pk-btn pk-btn--primary" disabled={loading || refreshing} onClick={() => void refresh()}>
          {refreshing ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>
      <p className="integ-intro">
        Read-only status from the running server (environment + database overrides). To edit API keys and Razorpay
        secrets, use{' '}
        <Link to="/api-keys">Access keys</Link>.
      </p>

      {err && <AdminErrorBanner message={err} devDetail={errDev} />}

      {loading && <p className="integ-loading">Loading…</p>}

      {data && !loading && (
        <div className="integ-grid">
          {ORDER.map(({ key, title }) => {
            const v = data[key] as IntegEntry | undefined
            if (!v) return null
            const on = Boolean(v.configured)
            return (
              <div key={key} className="integ-card">
                <div className="integ-card-top">
                  <span className="integ-card-title">{title}</span>
                  <span className={`integ-pill integ-pill--${on ? 'on' : 'off'}`}>{on ? 'Ready' : 'Not set'}</span>
                </div>
                {v.provider != null && v.provider !== '' && (
                  <div className="integ-card-meta">
                    Provider: <code>{v.provider}</code>
                  </div>
                )}
                {v.base_url != null && v.base_url !== '' && (
                  <div className="integ-card-meta">
                    Base URL: <code>{v.base_url}</code>
                  </div>
                )}
              </div>
            )
          })}
        </div>
      )}
    </section>
  )
}
