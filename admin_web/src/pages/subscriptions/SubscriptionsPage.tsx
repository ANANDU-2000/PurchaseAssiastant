import { useCallback, useEffect, useState } from 'react'
import { AdminErrorBanner } from '../../components/AdminErrorBanner'
import { adminGet, devErrorDetail, userSafePageError } from '../../lib/api'

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

function formatWhen(iso: string | null): string {
  if (!iso) return '—'
  try {
    return new Date(iso).toLocaleString()
  } catch {
    return iso
  }
}

export default function SubscriptionsPage() {
  const [subs, setSubs] = useState<SubRow[] | null>(null)
  const [pays, setPays] = useState<PayRow[] | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [errDev, setErrDev] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)

  const load = useCallback(async () => {
    const [s, p] = await Promise.all([
      adminGet<{ items: SubRow[] }>('/v1/admin/billing/subscriptions'),
      adminGet<{ items: PayRow[] }>('/v1/admin/billing/payments'),
    ])
    setSubs(s.items ?? [])
    setPays(p.items ?? [])
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
    <section className="admin-data-page subscriptions-page">
      <div className="admin-page-head">
        <h1>Subscriptions & payments</h1>
        <button type="button" className="pk-btn pk-btn--primary" disabled={loading || refreshing} onClick={() => void refresh()}>
          {refreshing ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>
      <p className="admin-data-intro">
        Per-business Razorpay orders and subscription flags. Patch exemptions via API or future UI.
      </p>

      {err && <AdminErrorBanner message={err} devDetail={errDev} />}

      {loading && <p className="admin-data-empty">Loading…</p>}

      {subs && pays && !loading && (
        <>
          <h2 className="admin-data-section-title">Business subscriptions</h2>
          {subs.length === 0 ? (
            <p className="admin-data-empty">No subscription rows.</p>
          ) : (
            <div className="admin-table-wrap">
              <table className="admin-table">
                <thead>
                  <tr>
                    <th>Business</th>
                    <th>Plan</th>
                    <th>Status</th>
                    <th>WA / AI</th>
                    <th>Exempt</th>
                  </tr>
                </thead>
                <tbody>
                  {subs.map((r) => (
                    <tr key={r.business_id}>
                      <td>{r.business_name}</td>
                      <td className="admin-table-mono">{r.plan_code}</td>
                      <td>{r.status}</td>
                      <td className="admin-table-muted">
                        {r.whatsapp_addon ? 'WA ' : ''}
                        {r.ai_addon ? 'AI' : ''}
                        {!r.whatsapp_addon && !r.ai_addon ? '—' : ''}
                      </td>
                      <td>{r.admin_exempt ? 'yes' : 'no'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          <h2 className="admin-data-section-title">Recent payments</h2>
          {pays.length === 0 ? (
            <p className="admin-data-empty">No payments.</p>
          ) : (
            <div className="admin-table-wrap">
              <table className="admin-table">
                <thead>
                  <tr>
                    <th>Business</th>
                    <th className="admin-table-num">Amount (₹)</th>
                    <th>Status</th>
                    <th>Order</th>
                    <th>Paid</th>
                  </tr>
                </thead>
                <tbody>
                  {pays.map((r, i) => (
                    <tr key={`${r.business_id}-${r.razorpay_order_id ?? 'order'}-${r.paid_at ?? i}`}>
                      <td className="admin-table-mono">{r.business_id.slice(0, 8)}…</td>
                      <td className="admin-table-num">{(r.amount_paise / 100).toFixed(2)}</td>
                      <td>{r.status}</td>
                      <td className="admin-table-mono">{r.razorpay_order_id ?? '—'}</td>
                      <td className="admin-table-muted">{formatWhen(r.paid_at)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
    </section>
  )
}
