import { useCallback, useEffect, useState } from 'react'
import { AdminErrorBanner } from '../../components/AdminErrorBanner'
import { adminGet, devErrorDetail, getAdminToken, userSafePageError } from '../../lib/api'

type WhatsappStats = {
  messages_24h?: number | null
  delivery_rate?: number | null
  note?: string
}

export default function WhatsAppPage() {
  const [data, setData] = useState<WhatsappStats | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [errDev, setErrDev] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)

  const fetchStats = useCallback(async () => {
    return adminGet<WhatsappStats>('/v1/admin/whatsapp-stats')
  }, [])

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      setLoading(true)
      setErr(null)
      setErrDev(null)
      if (!getAdminToken()) {
        setErr('Sign in to view WhatsApp stats.')
        setLoading(false)
        return
      }
      try {
        const d = await fetchStats()
        if (!cancelled) setData(d)
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
  }, [fetchStats])

  async function refresh() {
    setRefreshing(true)
    setErr(null)
    setErrDev(null)
    if (!getAdminToken()) {
      setErr('Sign in to view WhatsApp stats.')
      setRefreshing(false)
      return
    }
    try {
      const d = await fetchStats()
      setData(d)
    } catch (e: unknown) {
      setErr(userSafePageError(e))
      setErrDev(devErrorDetail(e))
    } finally {
      setRefreshing(false)
    }
  }

  return (
    <section className="admin-data-page whatsapp-page">
      <div className="admin-page-head">
        <h1>WhatsApp</h1>
        <button type="button" className="pk-btn pk-btn--primary" disabled={loading || refreshing} onClick={() => void refresh()}>
          {refreshing ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>
      <p className="admin-data-intro">Message volume and delivery metrics from the admin API.</p>

      {err && <AdminErrorBanner message={err} devDetail={errDev} />}

      {loading && <p className="admin-data-empty">Loading…</p>}

      {data && !loading && (
        <>
          <div className="metric-grid">
            <div className="metric-card">
              <div className="metric-card-label">Messages (24h)</div>
              <div className="metric-card-value">{data.messages_24h ?? '—'}</div>
            </div>
            <div className="metric-card">
              <div className="metric-card-label">Delivery rate</div>
              <div className="metric-card-value">{data.delivery_rate ?? '—'}</div>
            </div>
          </div>
          {data.note && <p className="admin-data-note">{data.note}</p>}
        </>
      )}
    </section>
  )
}
