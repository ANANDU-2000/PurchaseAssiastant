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
        <details>
          <summary>Technical details</summary>
          <pre className="overview-error-detail">{devDetail}</pre>
        </details>
      ) : null}
    </div>
  )
}
