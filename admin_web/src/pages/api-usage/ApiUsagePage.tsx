import { useEffect, useState } from 'react'
import { adminGet } from '../../lib/api'

export default function ApiUsagePage() {
  const [data, setData] = useState<unknown>(null)
  const [err, setErr] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const d = await adminGet('/v1/admin/api-usage')
        if (!cancelled) setData(d)
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
      <h1>API usage</h1>
      {err && <p style={{ color: 'crimson' }}>{err}</p>}
      {data && (
        <pre style={{ background: '#111', color: '#ddd', padding: 12, overflow: 'auto' }}>
          {JSON.stringify(data, null, 2)}
        </pre>
      )}
    </section>
  )
}
