import { type FormEvent, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { adminPost, apiBase, devErrorDetail, setAdminToken, userSafeLoginError } from '../../lib/api'

export default function LoginPage() {
  const nav = useNavigate()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [err, setErr] = useState<string | null>(null)
  const [errDev, setErrDev] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setErr(null)
    setErrDev(null)
    setBusy(true)
    try {
      const res = await adminPost<{ access_token: string }>('/v1/admin/login', { email, password })
      setAdminToken(res.access_token)
      nav('/', { replace: true })
    } catch (e: unknown) {
      setErr(userSafeLoginError(e))
      setErrDev(devErrorDetail(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="login-page">
      <div className="login-card">
        <h1>Operator Console</h1>
        <p className="login-hint">Sign in with your administrator email and password.</p>
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
          {errDev && (
            <details style={{ marginTop: '0.5rem', fontSize: '0.78rem', color: 'var(--admin-text-muted)' }}>
              <summary style={{ cursor: 'pointer' }}>Technical details</summary>
              <pre
                style={{
                  marginTop: '0.35rem',
                  whiteSpace: 'pre-wrap',
                  wordBreak: 'break-word',
                  maxHeight: 160,
                  overflow: 'auto',
                }}
              >
                {errDev}
              </pre>
            </details>
          )}
          <button type="submit" disabled={busy}>
            {busy ? 'Signing in…' : 'Sign in'}
          </button>
        </form>
        {import.meta.env.DEV && (
          <p
            className="login-hint"
            style={{ marginTop: '1.25rem', fontSize: '0.78rem', opacity: 0.85 }}
          >
            Dev: service URL <code>{apiBase()}</code>
          </p>
        )}
      </div>
    </div>
  )
}
