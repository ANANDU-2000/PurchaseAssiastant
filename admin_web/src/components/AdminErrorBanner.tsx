import type { ReactNode } from 'react'

/** Operator-friendly error with optional dev-only technical block. */
export function AdminErrorBanner({
  message,
  devDetail,
}: {
  message: ReactNode
  devDetail?: string | null
}) {
  return (
    <div className="overview-error">
      <p>{message}</p>
      {devDetail ? (
        <details style={{ marginTop: '0.65rem' }}>
          <summary style={{ cursor: 'pointer', fontSize: '0.82rem', color: 'var(--admin-text-muted)' }}>
            Technical details
          </summary>
          <pre className="overview-error-detail" style={{ marginTop: '0.5rem' }}>
            {devDetail}
          </pre>
        </details>
      ) : null}
    </div>
  )
}
