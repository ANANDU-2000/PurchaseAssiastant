import { useEffect, useState } from 'react'
import { adminGet, userSafePageError } from '../../lib/api'

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
        if (!cancelled) setErr(userSafePageError(e))
      }
    })()
    return () => {
      cancelled = true
    }
  }, [])

  const rows = data?.per_user ?? []

  return (
    <section className="stub-page">
      <h1>Usage</h1>
      {data?.note && (
        <p className="stub-page__hint" style={{ fontSize: 14 }}>
          {data.note}
          {data.generated_at && (
            <>
              {' '}
              — <code>{data.generated_at}</code>
            </>
          )}
        </p>
      )}
      {err && <p className="stub-page__error">{err}</p>}
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
      {import.meta.env.DEV && data != null && (
        <details style={{ marginTop: 16 }}>
          <summary style={{ cursor: 'pointer', color: 'var(--admin-text-muted)' }}>Technical details (dev)</summary>
          <pre
            style={{
              background: 'var(--admin-elevated)',
              color: 'var(--admin-text-muted)',
              padding: 12,
              overflow: 'auto',
              fontSize: 12,
              borderRadius: 8,
            }}
          >
            {JSON.stringify(data as object, null, 2)}
          </pre>
        </details>
      )}
    </section>
  )
}
