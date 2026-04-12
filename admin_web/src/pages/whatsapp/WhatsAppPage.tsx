import { useEffect, useState } from 'react'
import { adminGet, getAdminToken, userSafePageError } from '../../lib/api'

type WhatsappStats = {
  messages_24h?: number | null
  delivery_rate?: number | null
  note?: string
}

export default function WhatsAppPage() {
  const [data, setData] = useState<WhatsappStats | null>(null)
  const [err, setErr] = useState<string | null>(null)

  useEffect(() => {
    const t = getAdminToken()
    if (!t) {
      setErr('Sign in to view WhatsApp stats.')
      return
    }
    adminGet<WhatsappStats>('/v1/admin/whatsapp-stats')
      .then(setData)
      .catch((e: unknown) => setErr(userSafePageError(e)))
  }, [])

  return (
    <div className="stub-page">
      <h1>WhatsApp</h1>
      {err && <p className="stub-page__error">{err}</p>}
      {data && (
        <div className="metric-grid">
          <div className="metric-card">
            <div className="metric-card-label">Messages (24h)</div>
            <div className="metric-card-value">{data.messages_24h ?? '—'}</div>
          </div>
          <div className="metric-card">
            <div className="metric-card-label">Delivery rate</div>
            <div className="metric-card-value">{data.delivery_rate ?? '—'}</div>
          </div>
        </div>
      )}
      {data?.note && <p className="stub-page__hint">{data.note}</p>}
    </div>
  )
}
