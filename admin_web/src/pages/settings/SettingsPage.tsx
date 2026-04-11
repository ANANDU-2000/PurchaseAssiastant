import { apiBase } from '../../lib/api'

export default function SettingsPage() {
  return (
    <section>
      <h1>Super admin settings</h1>
      <p>
        This build does not include a separate admin login UI. Use a super-admin JWT from the mobile OTP bootstrap flow and set{' '}
        <code>VITE_ADMIN_BEARER</code> in <code>.env.local</code>.
      </p>
      <p>
        API base: <code>{apiBase()}</code>
      </p>
      <p style={{ opacity: 0.75 }}>
        Future: profile, session list, and security policy forms backed by dedicated admin endpoints.
      </p>
    </section>
  )
}
