import { useEffect, useState } from 'react'
import { adminGet, userSafePageError } from '../../lib/api'

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

export default function UsersPage() {
  const [data, setData] = useState<{ items: UserRow[]; total: number } | null>(null)
  const [err, setErr] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const d = await adminGet<{ items: UserRow[]; total: number }>('/v1/admin/users')
        if (!cancelled) setData({ items: d.items ?? [], total: d.total ?? 0 })
      } catch (e: unknown) {
        if (!cancelled) setErr(userSafePageError(e))
      }
    })()
    return () => {
      cancelled = true
    }
  }, [])

  return (
    <section className="stub-page">
      <h1>Users</h1>
      <p className="stub-page__hint" style={{ marginBottom: 12 }}>
        Customer accounts ({data?.total ?? '—'} total). Password and Google sign-in are shown per row.
      </p>
      {err && <p className="stub-page__error">{err}</p>}
      {data && (
        <table style={{ borderCollapse: 'collapse', width: '100%', maxWidth: 960 }}>
          <thead>
            <tr>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ccc', padding: '8px 4px' }}>Email</th>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ccc' }}>Username</th>
              <th style={{ textAlign: 'right', borderBottom: '1px solid #ccc' }}>Entries</th>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ccc' }}>Admin</th>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ccc' }}>Auth</th>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ccc' }}>Created</th>
            </tr>
          </thead>
          <tbody>
            {data.items.map((u) => (
              <tr key={u.id}>
                <td style={{ padding: '8px 4px' }}>{u.email}</td>
                <td style={{ fontFamily: 'monospace', fontSize: 13 }}>{u.username}</td>
                <td style={{ textAlign: 'right' }}>{u.total_entries ?? '—'}</td>
                <td>{u.is_super_admin ? 'yes' : '—'}</td>
                <td style={{ fontSize: 13 }}>
                  {u.has_password && 'password '}
                  {u.google_linked && 'google '}
                  {!u.has_password && !u.google_linked && '—'}
                </td>
                <td style={{ fontSize: 13 }}>{u.created_at ?? '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {data && data.items.length === 0 && !err && <p>No users.</p>}
    </section>
  )
}
