import { useEffect, useState } from 'react'
import { adminGet } from '../../lib/api'

type Biz = { id: string; name: string; created_at: string | null }

export default function BusinessesPage() {
  const [items, setItems] = useState<Biz[]>([])
  const [err, setErr] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const data = await adminGet<{ items: Biz[] }>('/v1/admin/businesses')
        if (!cancelled) setItems(data.items ?? [])
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
      <h1>Businesses</h1>
      <p style={{ color: '#555', marginBottom: 12 }}>Workspaces (tenants) registered in HEXA.</p>
      {err && <p style={{ color: 'crimson' }}>{err}</p>}
      <table style={{ borderCollapse: 'collapse', width: '100%', maxWidth: 720 }}>
        <thead>
          <tr>
            <th style={{ textAlign: 'left', borderBottom: '1px solid #ccc' }}>Name</th>
            <th style={{ textAlign: 'left', borderBottom: '1px solid #ccc' }}>Id</th>
            <th style={{ textAlign: 'left', borderBottom: '1px solid #ccc' }}>Created</th>
          </tr>
        </thead>
        <tbody>
          {items.map((b) => (
            <tr key={b.id}>
              <td style={{ padding: '8px 0' }}>{b.name}</td>
              <td style={{ fontFamily: 'monospace', fontSize: 12 }}>{b.id}</td>
              <td>{b.created_at ?? '—'}</td>
            </tr>
          ))}
        </tbody>
      </table>
      {items.length === 0 && !err && <p>No businesses (or still loading).</p>}
    </section>
  )
}
