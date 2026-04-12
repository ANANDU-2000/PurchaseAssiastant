import { apiBase } from '../../lib/api'

export default function SettingsPage() {
  return (
    <section className="stub-page">
      <h1>Console settings</h1>
      <p className="stub-page__hint">
        Workspace preferences and security options will appear here as they roll out. Sign in from the login page to
        access the console.
      </p>
      {import.meta.env.DEV && (
        <p className="stub-page__hint" style={{ marginTop: '1rem', fontSize: '0.85rem' }}>
          Dev: connected service <code>{apiBase()}</code>
        </p>
      )}
    </section>
  )
}
