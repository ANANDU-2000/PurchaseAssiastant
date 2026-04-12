import { useEffect, useState } from 'react'
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

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const m = await adminGet<Stats>('/v1/admin/stats')
        if (!cancelled) setData(m)
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
  }, [])

  return (
    <section className="overview-page">
      <h1>Overview</h1>
      <p className="overview-intro">
        Snapshot of accounts and purchase activity. Need access?{' '}
        <Link to="/login">Sign in</Link> with an administrator account.
      </p>
      {err && <AdminErrorBanner message={err} devDetail={errDev} />}
      {data && (
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
