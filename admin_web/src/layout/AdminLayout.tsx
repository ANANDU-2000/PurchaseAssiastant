import { NavLink, Outlet } from 'react-router-dom'

const nav = [
  { to: '/', label: 'Overview' },
  { to: '/users', label: 'Users' },
  { to: '/subscriptions', label: 'Subscriptions' },
  { to: '/api-usage', label: 'API usage' },
  { to: '/feature-flags', label: 'Feature flags' },
  { to: '/logs', label: 'Logs' },
  { to: '/integrations', label: 'Integrations' },
  { to: '/settings', label: 'Settings' },
]

export default function AdminLayout() {
  return (
    <div className="admin-root">
      <aside className="admin-nav">
        <div className="brand">HEXA Admin</div>
        <nav>
          {nav.map((item) => (
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
