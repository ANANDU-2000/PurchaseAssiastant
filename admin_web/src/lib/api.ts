const STORAGE_KEY = 'hexa_admin_bearer'

const base = (import.meta.env.VITE_API_BASE_URL as string | undefined) ?? 'http://localhost:8000'

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

export async function adminGet<T>(path: string): Promise<T> {
  const res = await fetch(`${base.replace(/\/$/, '')}${path}`, { headers: headersGet() })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`${res.status} ${text}`)
  }
  return res.json() as Promise<T>
}

export async function adminPost<T>(path: string, body: unknown): Promise<T> {
  const res = await fetch(`${base.replace(/\/$/, '')}${path}`, {
    method: 'POST',
    headers: headersJson(),
    body: JSON.stringify(body),
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`${res.status} ${text}`)
  }
  return res.json() as Promise<T>
}

export async function adminPatch<T>(path: string, body: unknown): Promise<T> {
  const res = await fetch(`${base.replace(/\/$/, '')}${path}`, {
    method: 'PATCH',
    headers: headersJson(),
    body: JSON.stringify(body),
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`${res.status} ${text}`)
  }
  return res.json() as Promise<T>
}

export function apiBase(): string {
  return base.replace(/\/$/, '')
}
