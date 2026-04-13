import { Link } from 'react-router-dom'
import { apiBase, getAdminToken } from '../../lib/api'

const SHORTCUTS: { to: string; title: string; desc: string }[] = [
  {
    to: '/api-keys',
    title: 'Access keys',
    desc: 'Override AI, 360dialog, and Razorpay secrets in the database (no redeploy).',
  },
  {
    to: '/integrations',
    title: 'Integrations',
    desc: 'Read-only status for OpenAI, OCR, STT, S3, Razorpay, Sentry, Redis, and WhatsApp.',
  },
  {
    to: '/feature-flags',
    title: 'Feature flags',
    desc: 'Toggle AI, voice, OCR, realtime, and WhatsApp bot features.',
  },
  {
    to: '/logs',
    title: 'Audit logs',
    desc: 'Recent super-admin actions (e.g. platform integration updates).',
  },
  {
    to: '/subscriptions',
    title: 'Subscriptions',
    desc: 'Per-business billing and Razorpay order linkage.',
  },
]

export default function SettingsPage() {
  const hasToken = Boolean(getAdminToken()?.trim())

  return (
    <section className="admin-data-page admin-settings-page">
      <div className="admin-page-head">
        <h1>Console settings</h1>
      </div>
      <p className="admin-data-intro">
        Shortcuts and read-only connection details for this browser session. Preference storage for the admin UI may be
        added later; feature toggles and secrets are managed on the pages below.
      </p>

      <h2 className="settings-h2">Shortcuts</h2>
      <div className="settings-shortcuts">
        {SHORTCUTS.map((s) => (
          <Link key={s.to} to={s.to} className="settings-shortcut">
            <span className="settings-shortcut-title">{s.title}</span>
            <span className="settings-shortcut-desc">{s.desc}</span>
            <span className="settings-shortcut-chevron" aria-hidden>
              →
            </span>
          </Link>
        ))}
      </div>

      <h2 className="settings-h2">Connection</h2>
      <dl className="settings-dl">
        <div>
          <dt>API base</dt>
          <dd>
            <code>{apiBase()}</code>
          </dd>
        </div>
        <div>
          <dt>Admin bearer token</dt>
          <dd>{hasToken ? 'Saved in this browser (use Log out to clear)' : 'Not set — sign in from the login page'}</dd>
        </div>
      </dl>

      {import.meta.env.DEV && (
        <p className="settings-dev">
          <strong>Dev</strong>: <code>VITE_API_BASE_URL</code> ={' '}
          <code>{String((import.meta.env.VITE_API_BASE_URL as string | undefined) ?? '') || '(empty → same-origin proxy)'}</code>
        </p>
      )}
    </section>
  )
}
