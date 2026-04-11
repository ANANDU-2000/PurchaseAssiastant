import { useEffect, useState } from 'react'
import { adminGet, apiBase } from '../../lib/api'

type Metrics = { users: number; businesses: number; entries_today: number }

export default function OverviewPage() {
  const [data, setData] = useState<Metrics | null>(null)
  const [err, setErr] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const m = await adminGet<Metrics>('/v1/admin/metrics')
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
    <section>
      <h1>Overview</h1>
      <p>
        API: <code>{apiBase()}</code> — set <code>VITE_API_BASE_URL</code> and super-admin{' '}
        <code>VITE_ADMIN_BEARER</code> in <code>.env.local</code>.
      </p>
      {err && (
        <p style={{ color: 'crimson' }}>
          {err} (expected until a valid super-admin JWT is configured.)
        </p>
      )}
      {data && (
        <ul>
          <li>Users: {data.users}</li>
          <li>Businesses: {data.businesses}</li>
          <li>Entries today: {data.entries_today}</li>
        </ul>
      )}
    </section>
  )
}
