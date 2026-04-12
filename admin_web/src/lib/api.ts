const STORAGE_KEY = 'hexa_admin_bearer'

/** Empty VITE_API_BASE_URL → same-origin + Vite proxy to :8000 (fixes CORS / Failed to fetch in dev). */
function apiRoot(): string {
  const v = (import.meta.env.VITE_API_BASE_URL as string | undefined)?.trim()
  if (v && v.length > 0) return v.replace(/\/$/, '')
  return ''
}

export function getAdminToken(): string | undefined {
  if (typeof window === 'undefined') {
    return (import.meta.env.VITE_ADMIN_BEARER as string | undefined)?.trim()
  }
  return (
    localStorage.getItem(STORAGE_KEY)?.trim() ||
    (import.meta.env.VITE_ADMIN_BEARER as string | undefined)?.trim()
  )
}

export function setAdminToken(token: string | null): void {
  if (typeof window === 'undefined') return
  if (token) localStorage.setItem(STORAGE_KEY, token)
  else localStorage.removeItem(STORAGE_KEY)
}

function headersJson(): HeadersInit {
  const h: Record<string, string> = {
    Accept: 'application/json',
    'Content-Type': 'application/json',
  }
  const token = getAdminToken()
  if (token) {
    h.Authorization = `Bearer ${token}`
  }
  return h
}

function headersGet(): HeadersInit {
  const h: Record<string, string> = { Accept: 'application/json' }
  const token = getAdminToken()
  if (token) {
    h.Authorization = `Bearer ${token}`
  }
  return h
}

/** FastAPI errors often look like `{"detail":"..."}` or validation arrays — surface the full message. */
function formatFailedApiResponse(res: Response, bodyText: string): string {
  const head = `HTTP ${res.status} ${res.statusText}`
  const raw = bodyText.trim() || '(empty response body)'
  try {
    const j = JSON.parse(bodyText) as { detail?: unknown }
    if (j.detail === undefined) {
      return `${head}\n\n${raw}`
    }
    const d = j.detail
    if (typeof d === 'string') {
      return `${head}\n\n${d}`
    }
    if (Array.isArray(d)) {
      const parts = d.map((item) =>
        typeof item === 'object' && item !== null && 'msg' in item
          ? String((item as { msg?: string }).msg ?? JSON.stringify(item))
          : JSON.stringify(item),
      )
      return `${head}\n\n${parts.join('\n')}`
    }
    return `${head}\n\n${JSON.stringify(d, null, 2)}`
  } catch {
    return `${head}\n\n${raw}`
  }
}

async function throwUnlessOk(res: Response): Promise<void> {
  if (res.ok) return
  const text = await res.text()
  throw new Error(formatFailedApiResponse(res, text))
}

export async function adminGet<T>(path: string): Promise<T> {
  const res = await fetch(`${apiRoot()}${path}`, { headers: headersGet() })
  await throwUnlessOk(res)
  return res.json() as Promise<T>
}

export async function adminPost<T>(path: string, body: unknown): Promise<T> {
  const res = await fetch(`${apiRoot()}${path}`, {
    method: 'POST',
    headers: headersJson(),
    body: JSON.stringify(body),
  })
  await throwUnlessOk(res)
  return res.json() as Promise<T>
}

export async function adminPatch<T>(path: string, body: unknown): Promise<T> {
  const res = await fetch(`${apiRoot()}${path}`, {
    method: 'PATCH',
    headers: headersJson(),
    body: JSON.stringify(body),
  })
  await throwUnlessOk(res)
  return res.json() as Promise<T>
}

export async function adminPut<T>(path: string, body: unknown): Promise<T> {
  const res = await fetch(`${apiRoot()}${path}`, {
    method: 'PUT',
    headers: headersJson(),
    body: JSON.stringify(body),
  })
  await throwUnlessOk(res)
  return res.json() as Promise<T>
}

export function apiBase(): string {
  const v = (import.meta.env.VITE_API_BASE_URL as string | undefined)?.trim()
  if (v && v.length > 0) return v.replace(/\/$/, '')
  if (typeof window !== 'undefined') {
    return `${window.location.origin} (proxies /v1 → http://127.0.0.1:8000)`
  }
  return 'http://127.0.0.1:8000'
}

function errorText(err: unknown): string {
  return err instanceof Error ? err.message : String(err)
}

/** Human-readable sign-in failure (no HTTP dumps in production). */
export function userSafeLoginError(err: unknown): string {
  const m = errorText(err)
  if (/Failed to fetch|Load failed|NetworkError/i.test(m)) {
    return "Can't reach the service. Check your network and try again."
  }
  if (/\b401\b|Unauthorized/i.test(m)) {
    return 'Email or password is incorrect.'
  }
  if (/\b403\b|Forbidden/i.test(m)) {
    return 'This account cannot use the admin console.'
  }
  if (/\b5\d\d\b/.test(m)) {
    return 'The service is having trouble. Please try again shortly.'
  }
  const detail = extractFastApiDetail(m)
  if (detail) return detail.length > 180 ? `${detail.slice(0, 177)}…` : detail
  if (import.meta.env.DEV) return m
  return 'Sign-in did not work. Try again.'
}

/** Human-readable message for data-loading failures across admin pages. */
export function userSafePageError(err: unknown): string {
  const m = errorText(err)
  if (/Failed to fetch|Load failed|NetworkError/i.test(m)) {
    return "Can't connect right now. Check your network and try again."
  }
  if (/\b401\b|Unauthorized/i.test(m)) {
    return 'Your session expired. Sign in again from the login page.'
  }
  if (/\b403\b|Forbidden/i.test(m)) {
    return "You don't have access to this."
  }
  if (/\b5\d\d\b/.test(m)) {
    return 'The service is having trouble. Please try again shortly.'
  }
  const detail = extractFastApiDetail(m)
  if (detail) return detail.length > 220 ? `${detail.slice(0, 217)}…` : detail
  if (import.meta.env.DEV) return m
  return 'Something went wrong. Please try again.'
}

function extractFastApiDetail(message: string): string | null {
  const parts = message.split('\n\n')
  if (parts.length < 2) return null
  const body = parts.slice(1).join('\n\n').trim()
  try {
    const j = JSON.parse(body) as { detail?: unknown }
    if (typeof j.detail === 'string') return j.detail
    if (Array.isArray(j.detail) && j.detail[0] && typeof j.detail[0] === 'object' && j.detail[0] !== null) {
      const msg = (j.detail[0] as { msg?: string }).msg
      if (typeof msg === 'string') return msg
    }
  } catch {
    const line = body.split('\n')[0]
    if (line && !line.startsWith('{') && line.length < 300) return line
  }
  return null
}

/** Optional technical detail for developer builds only. */
export function devErrorDetail(err: unknown): string | null {
  if (!import.meta.env.DEV) return null
  return errorText(err)
}
