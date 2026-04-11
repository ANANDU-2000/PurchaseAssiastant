import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import AdminLayout from './layout/AdminLayout'
import ApiUsagePage from './pages/api-usage/ApiUsagePage'
import FeatureFlagsPage from './pages/feature-flags/FeatureFlagsPage'
import IntegrationsPage from './pages/integrations/IntegrationsPage'
import LogsPage from './pages/logs/LogsPage'
import OverviewPage from './pages/overview/OverviewPage'
import SettingsPage from './pages/settings/SettingsPage'
import SubscriptionsPage from './pages/subscriptions/SubscriptionsPage'
import UsersPage from './pages/users/UsersPage'
import './App.css'

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<AdminLayout />}>
          <Route index element={<OverviewPage />} />
          <Route path="users" element={<UsersPage />} />
          <Route path="subscriptions" element={<SubscriptionsPage />} />
          <Route path="api-usage" element={<ApiUsagePage />} />
          <Route path="feature-flags" element={<FeatureFlagsPage />} />
          <Route path="logs" element={<LogsPage />} />
          <Route path="integrations" element={<IntegrationsPage />} />
          <Route path="settings" element={<SettingsPage />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Route>
      </Routes>
    </BrowserRouter>
  )
}
