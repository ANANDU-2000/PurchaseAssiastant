import { useEffect, useState } from 'react'
import { adminGet } from '../../lib/api'

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

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const d = await adminGet<Summary>('/v1/admin/api-usage-summary')
        if (!cancelled) setData(d)
      } catch (e: unknown) {
        if (!cancelled) setErr(e instanceof Error ? e.message : String(e))
      }
    })()
    return () => {
      cancelled = true
    }
  }, [])

  const rows = data?.per_user ?? []

  return (
    <section>
      <h1>API usage</h1>
      {data?.note && (
        <p style={{ color: '#64748b', fontSize: 14 }}>
          {data.note}
          {data.generated_at && (
            <>
              {' '}
              — <code>{data.generated_at}</code>
            </>
          )}
        </p>
      )}
      {err && <p style={{ color: 'crimson' }}>{err}</p>}
      {rows.length > 0 && (
        <table style={{ borderCollapse: 'collapse', width: '100%', maxWidth: 960, marginTop: 16 }}>
          <thead>
            <tr>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ccc', padding: '8px 4px' }}>Email</th>
              <th style={{ textAlign: 'right', borderBottom: '1px solid #ccc' }}>Entries</th>
              <th style={{ textAlign: 'right', borderBottom: '1px solid #ccc' }}>WA msg</th>
              <th style={{ textAlign: 'right', borderBottom: '1px solid #ccc' }}>AI</th>
              <th style={{ textAlign: 'right', borderBottom: '1px solid #ccc' }}>Voice</th>
              <th style={{ textAlign: 'right', borderBottom: '1px solid #ccc' }}>Est. ₹</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((u) => (
              <tr key={u.user_id}>
                <td style={{ padding: '8px 4px', fontSize: 14 }}>{u.email}</td>
                <td style={{ textAlign: 'right', fontSize: 14 }}>{u.entries_total}</td>
                <td style={{ textAlign: 'right', fontSize: 14, color: '#94a3b8' }}>
                  {u.whatsapp_messages_24h ?? '—'}
                </td>
                <td style={{ textAlign: 'right', fontSize: 14, color: '#94a3b8' }}>{u.ai_calls_24h ?? '—'}</td>
                <td style={{ textAlign: 'right', fontSize: 14, color: '#94a3b8' }}>{u.voice_minutes_24h ?? '—'}</td>
                <td style={{ textAlign: 'right', fontSize: 14 }}>{u.estimated_cost_inr.toFixed(2)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {data != null && rows.length === 0 && !err && <p>No usage rows yet.</p>}
      {data != null && (
        <details style={{ marginTop: 16 }}>
          <summary style={{ cursor: 'pointer', color: '#64748b' }}>Raw JSON</summary>
          <pre style={{ background: '#111', color: '#ddd', padding: 12, overflow: 'auto', fontSize: 12 }}>
            {JSON.stringify(data as object, null, 2)}
          </pre>
        </details>
      )}
    </section>
  )
}
