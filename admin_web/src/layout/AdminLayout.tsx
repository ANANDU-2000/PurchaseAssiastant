import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { setAdminToken } from '../lib/api'

const navItems = [
  { to: '/', label: 'Overview' },
  { to: '/users', label: 'Users' },
  { to: '/businesses', label: 'Businesses' },
  { to: '/subscriptions', label: 'Subscriptions' },
  { to: '/api-usage', label: 'API usage' },
  { to: '/feature-flags', label: 'Feature flags' },
  { to: '/logs', label: 'Logs' },
  { to: '/integrations', label: 'Integrations' },
  { to: '/settings', label: 'Settings' },
]

export default function AdminLayout() {
  const go = useNavigate()
  return (
    <div className="admin-root">
      <aside className="admin-nav">
        <div className="brand">HEXA Admin</div>
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
              {item.label}
            </NavLink>
          ))}
        </nav>
      </aside>
      <main className="admin-main">
        <Outlet />
      </main>
    </div>
  )
}
