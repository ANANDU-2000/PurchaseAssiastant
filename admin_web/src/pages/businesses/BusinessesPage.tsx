import { useCallback, useEffect, useState } from 'react'
import { AdminErrorBanner } from '../../components/AdminErrorBanner'
import { adminGet, devErrorDetail, userSafePageError } from '../../lib/api'

type Biz = { id: string; name: string; created_at: string | null }

function formatCreated(iso: string | null): string {
  if (!iso) return '—'
  try {
    return new Date(iso).toLocaleString()
  } catch {
    return iso
  }
}

export default function BusinessesPage() {
  const [items, setItems] = useState<Biz[] | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [errDev, setErrDev] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)

  const load = useCallback(async () => {
    const data = await adminGet<{ items: Biz[] }>('/v1/admin/businesses')
    setItems(data.items ?? [])
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
    <section className="admin-data-page businesses-page">
      <div className="admin-page-head">
        <h1>Businesses</h1>
        <button type="button" className="pk-btn pk-btn--primary" disabled={loading || refreshing} onClick={() => void refresh()}>
          {refreshing ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>
      <p className="admin-data-intro">Workspaces (tenants) registered in HEXA.</p>

      {err && <AdminErrorBanner message={err} devDetail={errDev} />}

      {loading && <p className="admin-data-empty">Loading…</p>}

      {items && !loading && (
        <>
          {items.length === 0 ? (
            <p className="admin-data-empty">No businesses.</p>
          ) : (
            <div className="admin-table-wrap">
              <table className="admin-table">
                <thead>
                  <tr>
                    <th>Name</th>
                    <th>Id</th>
                    <th>Created</th>
                  </tr>
                </thead>
                <tbody>
                  {items.map((b) => (
                    <tr key={b.id}>
                      <td>{b.name}</td>
                      <td className="admin-table-mono">{b.id}</td>
                      <td className="admin-table-muted">{formatCreated(b.created_at)}</td>
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
