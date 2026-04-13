import { useCallback, useEffect, useState } from 'react'
import { AdminErrorBanner } from '../../components/AdminErrorBanner'
import { adminGet, devErrorDetail, userSafePageError } from '../../lib/api'

type PerUser = {
  user_id: string
  email: string
  entries_total: number
  whatsapp_messages_24h: number | null
  ai_calls_24h: number | null
  voice_minutes_24h: number | null
  estimated_cost_inr: number
}

type Summary = {
  per_user?: PerUser[]
  note?: string
  generated_at?: string
  providers?: unknown
}

export default function ApiUsagePage() {
  const [data, setData] = useState<Summary | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [errDev, setErrDev] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)

  const load = useCallback(async () => {
    const d = await adminGet<Summary>('/v1/admin/api-usage-summary')
    setData(d)
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

  const rows = data?.per_user ?? []

  return (
    <section className="admin-data-page api-usage-page">
      <div className="admin-page-head">
        <h1>Usage</h1>
        <button type="button" className="pk-btn pk-btn--primary" disabled={loading || refreshing} onClick={() => void refresh()}>
          {refreshing ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>

      {data?.note && (
        <p className="admin-data-note">
          {data.note}
          {data.generated_at && (
            <>
              {' '}
              — <code>{data.generated_at}</code>
            </>
          )}
        </p>
      )}

      {err && <AdminErrorBanner message={err} devDetail={errDev} />}

      {loading && <p className="admin-data-empty">Loading…</p>}

      {data && !loading && (
        <>
          {rows.length === 0 ? (
            <p className="admin-data-empty">No usage rows yet.</p>
          ) : (
            <div className="admin-table-wrap">
              <table className="admin-table">
                <thead>
                  <tr>
                    <th>Email</th>
                    <th className="admin-table-num">Entries</th>
                    <th className="admin-table-num">WA msg</th>
                    <th className="admin-table-num">AI</th>
                    <th className="admin-table-num">Voice</th>
                    <th className="admin-table-num">Est. ₹</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((u) => (
                    <tr key={u.user_id}>
                      <td>{u.email}</td>
                      <td className="admin-table-num">{u.entries_total}</td>
                      <td className="admin-table-num admin-table-muted">{u.whatsapp_messages_24h ?? '—'}</td>
                      <td className="admin-table-num admin-table-muted">{u.ai_calls_24h ?? '—'}</td>
                      <td className="admin-table-num admin-table-muted">{u.voice_minutes_24h ?? '—'}</td>
                      <td className="admin-table-num">{u.estimated_cost_inr.toFixed(2)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}

      {import.meta.env.DEV && data != null && (
        <details className="admin-data-dev">
          <summary>Technical details (dev)</summary>
          <pre>{JSON.stringify(data as object, null, 2)}</pre>
        </details>
      )}
    </section>
  )
}
