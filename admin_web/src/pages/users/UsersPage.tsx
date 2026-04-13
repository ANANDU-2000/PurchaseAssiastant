import { useCallback, useEffect, useState } from 'react'
import { AdminErrorBanner } from '../../components/AdminErrorBanner'
import { adminGet, devErrorDetail, userSafePageError } from '../../lib/api'

type UserRow = {
  id: string
  email: string
  username: string
  name: string | null
  phone: string | null
  is_super_admin: boolean
  created_at: string | null
  has_password: boolean
  google_linked: boolean
  total_entries?: number
}

function formatCreated(iso: string | null): string {
  if (!iso) return '—'
  try {
    return new Date(iso).toLocaleString()
  } catch {
    return iso
  }
}

export default function UsersPage() {
  const [data, setData] = useState<{ items: UserRow[]; total: number } | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [errDev, setErrDev] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)

  const load = useCallback(async () => {
    const d = await adminGet<{ items: UserRow[]; total: number }>('/v1/admin/users')
    setData({ items: d.items ?? [], total: d.total ?? 0 })
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
    <section className="admin-data-page users-page">
      <div className="admin-page-head">
        <h1>Users</h1>
        <button type="button" className="pk-btn pk-btn--primary" disabled={loading || refreshing} onClick={() => void refresh()}>
          {refreshing ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>
      <p className="admin-data-intro">
        Customer accounts ({data?.total ?? '—'} total). Password and Google sign-in are shown per row.
      </p>

      {err && <AdminErrorBanner message={err} devDetail={errDev} />}

      {loading && <p className="admin-data-empty">Loading…</p>}

      {data && !loading && (
        <>
          {data.items.length === 0 ? (
            <p className="admin-data-empty">No users.</p>
          ) : (
            <div className="admin-table-wrap">
              <table className="admin-table">
                <thead>
                  <tr>
                    <th>Email</th>
                    <th>Username</th>
                    <th className="admin-table-num">Entries</th>
                    <th>Admin</th>
                    <th>Auth</th>
                    <th>Created</th>
                  </tr>
                </thead>
                <tbody>
                  {data.items.map((u) => (
                    <tr key={u.id}>
                      <td>{u.email}</td>
                      <td className="admin-table-mono">{u.username}</td>
                      <td className="admin-table-num">{u.total_entries ?? '—'}</td>
                      <td>{u.is_super_admin ? 'yes' : '—'}</td>
                      <td className="admin-table-muted">
                        {u.has_password && 'password '}
                        {u.google_linked && 'google '}
                        {!u.has_password && !u.google_linked && '—'}
                      </td>
                      <td className="admin-table-muted">{formatCreated(u.created_at)}</td>
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
