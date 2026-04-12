import { useEffect, useState } from 'react'
import { adminGet, userSafePageError } from '../../lib/api'

type Integ = Record<string, { configured?: boolean; provider?: string; base_url?: string }>

export default function IntegrationsPage() {
  const [data, setData] = useState<Integ | null>(null)
  const [err, setErr] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const d = await adminGet<Integ>('/v1/admin/integrations')
        if (!cancelled) setData(d)
      } catch (e: unknown) {
        if (!cancelled) setErr(userSafePageError(e))
      }
    })()
    return () => {
      cancelled = true
    }
  }, [])

  return (
    <section>
      <h1>Integrations</h1>
      {err && <p style={{ color: 'crimson' }}>{err}</p>}
      {data && (
        <ul>
          {Object.entries(data).map(([k, v]) => (
            <li key={k}>
              <strong>{k}</strong>: {v.configured ? 'configured' : 'not configured'}
              {v.provider ? ` (${v.provider})` : ''}
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
