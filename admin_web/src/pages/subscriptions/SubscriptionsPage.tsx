import { useEffect, useState } from 'react'
import { adminGet, userSafePageError } from '../../lib/api'

type SubRow = {
  business_id: string
  business_name: string
  plan_code: string
  status: string
  whatsapp_addon: boolean
  ai_addon: boolean
  admin_exempt: boolean
  monthly_base_paise: number
  monthly_addons_paise: number
}

type PayRow = {
  business_id: string
  amount_paise: number
  status: string
  razorpay_order_id: string | null
  paid_at: string | null
}

export default function SubscriptionsPage() {
  const [subs, setSubs] = useState<SubRow[] | null>(null)
  const [pays, setPays] = useState<PayRow[] | null>(null)
  const [err, setErr] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const [s, p] = await Promise.all([
          adminGet<{ items: SubRow[] }>('/v1/admin/billing/subscriptions'),
          adminGet<{ items: PayRow[] }>('/v1/admin/billing/payments'),
        ])
        if (!cancelled) {
          setSubs(s.items)
          setPays(p.items)
        }
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
      <h1>Subscriptions & payments</h1>
      <p>Per-business Razorpay orders and subscription flags. Patch exemptions via API or future UI.</p>
      {err && <p style={{ color: 'crimson' }}>{err}</p>}
      <h2>Business subscriptions</h2>
      {subs && (
        <table style={{ borderCollapse: 'collapse', width: '100%', maxWidth: 960 }}>
          <thead>
            <tr>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ccc' }}>Business</th>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ccc' }}>Plan</th>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ccc' }}>Status</th>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ccc' }}>WA / AI</th>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ccc' }}>Exempt</th>
            </tr>
          </thead>
          <tbody>
            {subs.map((r) => (
              <tr key={r.business_id}>
                <td style={{ padding: '6px 0' }}>{r.business_name}</td>
                <td>{r.plan_code}</td>
                <td>{r.status}</td>
                <td>
                  {r.whatsapp_addon ? 'WA ' : ''}
                  {r.ai_addon ? 'AI' : ''}
                </td>
                <td>{r.admin_exempt ? 'yes' : 'no'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <h2 style={{ marginTop: 24 }}>Recent payments</h2>
      {pays && (
        <table style={{ borderCollapse: 'collapse', width: '100%', maxWidth: 960 }}>
          <thead>
            <tr>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ccc' }}>Business</th>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ccc' }}>Amount (₹)</th>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ccc' }}>Status</th>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ccc' }}>Order</th>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ccc' }}>Paid</th>
            </tr>
          </thead>
          <tbody>
            {pays.map((r) => (
              <tr key={`${r.business_id}-${r.razorpay_order_id}`}>
                <td style={{ padding: '6px 0', fontSize: 12 }}>{r.business_id.slice(0, 8)}…</td>
                <td>{(r.amount_paise / 100).toFixed(2)}</td>
                <td>{r.status}</td>
                <td style={{ fontSize: 12 }}>{r.razorpay_order_id ?? '—'}</td>
                <td style={{ fontSize: 12 }}>{r.paid_at ?? '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  )
}
