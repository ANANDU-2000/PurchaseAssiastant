import { type FormEvent, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { adminPost, apiBase, setAdminToken } from '../../lib/api'

export default function LoginPage() {
  const nav = useNavigate()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [err, setErr] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setErr(null)
    setBusy(true)
    try {
      const res = await adminPost<{ access_token: string }>('/v1/admin/login', { email, password })
      setAdminToken(res.access_token)
      nav('/', { replace: true })
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="login-page">
      <div className="login-card">
        <h1>HEXA Admin</h1>
        <p className="login-hint">
          Backend: <code>{apiBase()}</code>
          <br />
          Configure <code>ADMIN_EMAIL</code>, <code>ADMIN_PASSWORD</code>, and <code>ADMIN_API_TOKEN</code> on the API.
        </p>
        <form onSubmit={onSubmit}>
          <label>
            Email
            <input
              type="email"
              autoComplete="username"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
            />
          </label>
          <label>
            Password
            <input
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
            />
          </label>
          {err && <p className="login-err">{err}</p>}
          <button type="submit" disabled={busy}>
            {busy ? 'Signing in…' : 'Sign in'}
          </button>
        </form>
      </div>
    </div>
  )
}
