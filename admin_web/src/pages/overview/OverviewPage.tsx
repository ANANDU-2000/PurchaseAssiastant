import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { adminGet, apiBase } from '../../lib/api'

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

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const m = await adminGet<Stats>('/v1/admin/stats')
        if (!cancelled) setData(m)
      } catch (e: unknown) {
        if (!cancelled) setErr(e instanceof Error ? e.message : String(e))
      }
    })()
    return () => {
      cancelled = true
    }
  }, [])

  return (
    <section className="overview-page">
      <h1>HEXA admin</h1>
      <p className="overview-intro">
        API: <code>{apiBase()}</code> — <Link to="/login">Sign in</Link> with <code>ADMIN_EMAIL</code> /{' '}
        <code>ADMIN_PASSWORD</code> (backend env), or set <code>VITE_ADMIN_BEARER</code> to <code>ADMIN_API_TOKEN</code> in{' '}
        <code>.env.local</code>.
      </p>
      {err && (
        <p className="overview-error">
          {err} (expected until a valid admin bearer token is configured.)
        </p>
      )}
      {data && (
        <>
          <div className="metric-grid">
            <MetricCard label="Total users" value={data.users} />
            <MetricCard label="Businesses" value={data.businesses} hint="Workspaces / orgs" />
            <MetricCard label="Entries today" value={data.entries_today} hint="Purchase entries (IST day)" />
            <MetricCard label="Entries (all time)" value={data.entries_total} />
          </div>
          <p className="overview-asof">Last refreshed: {new Date(data.as_of).toLocaleString()}</p>
        </>
      )}
    </section>
  )
}
