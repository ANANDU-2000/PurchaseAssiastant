import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { AdminErrorBanner } from '../../components/AdminErrorBanner'
import { adminGet, devErrorDetail, userSafePageError } from '../../lib/api'

type Stats = {
  users: number
  businesses: number
  entries_today: number
  entries_total: number
  as_of: string
}

function MetricCard({
  label,
  value,
  hint,
}: {
  label: string
  value: string | number
  hint?: string
}) {
  return (
    <div className="metric-card">
      <div className="metric-card-label">{label}</div>
      <div className="metric-card-value">{value}</div>
      {hint && <div className="metric-card-hint">{hint}</div>}
    </div>
  )
}

export default function OverviewPage() {
  const [data, setData] = useState<Stats | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [errDev, setErrDev] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)

  const load = useCallback(async () => {
    const m = await adminGet<Stats>('/v1/admin/stats')
    setData(m)
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

  return (
    <section className="admin-data-page overview-page">
      <div className="admin-page-head">
        <h1>Overview</h1>
        <button type="button" className="pk-btn pk-btn--primary" disabled={loading || refreshing} onClick={() => void refresh()}>
          {refreshing ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>
      <p className="admin-data-intro">
        Snapshot of accounts and purchase activity. Need access? <Link to="/login">Sign in</Link> with an administrator account.
      </p>

      {err && <AdminErrorBanner message={err} devDetail={errDev} />}

      {loading && <p className="admin-data-empty">Loading…</p>}

      {data && !loading && (
        <>
          <div className="metric-grid">
            <MetricCard label="Total users" value={data.users} />
            <MetricCard label="Businesses" value={data.businesses} hint="Workspaces" />
            <MetricCard label="Entries today" value={data.entries_today} hint="Purchase entries (local day)" />
            <MetricCard label="Entries (all time)" value={data.entries_total} />
          </div>
          <p className="overview-asof">Last refreshed: {new Date(data.as_of).toLocaleString()}</p>
        </>
      )}
    </section>
  )
}
