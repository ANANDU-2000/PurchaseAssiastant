import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { setAdminToken } from '../lib/api'

const navItems = [
  { to: '/', label: 'Overview', icon: '📊' },
  { to: '/users', label: 'Users', icon: '👤' },
  { to: '/businesses', label: 'Businesses', icon: '🏢' },
  { to: '/subscriptions', label: 'Subscriptions', icon: '💳' },
  { to: '/api-usage', label: 'Usage', icon: '📈' },
  { to: '/api-keys', label: 'Access keys', icon: '🔑' },
  { to: '/feature-flags', label: 'Feature flags', icon: '🚩' },
  { to: '/logs', label: 'Logs', icon: '📜' },
  { to: '/integrations', label: 'Integrations', icon: '🔌' },
  { to: '/whatsapp', label: 'WhatsApp', icon: '💬' },
  { to: '/settings', label: 'Settings', icon: '⚙️' },
]

export default function AdminLayout() {
  const go = useNavigate()
  return (
    <div className="admin-root">
      <aside className="admin-nav">
        <div className="brand">Purchase Assistant</div>
        <button
          type="button"
          className="logout-btn"
          onClick={() => {
            setAdminToken(null)
            go('/login', { replace: true })
          }}
        >
          Log out
        </button>
        <nav>
          {navItems.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.to === '/'}
              className={({ isActive }) => (isActive ? 'active' : undefined)}
            >
              <span className="admin-nav-icon" aria-hidden>
                {item.icon}
              </span>
              <span>{item.label}</span>
            </NavLink>
          ))}
        </nav>
        <footer className="admin-footer">
          <p>Purchase Assistant · operator console</p>
          <p className="admin-footer-muted">Signed-in sessions are stored in this browser only.</p>
        </footer>
      </aside>
      <main className="admin-main">
        <Outlet />
      </main>
    </div>
  )
}
