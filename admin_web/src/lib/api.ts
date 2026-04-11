const base = (import.meta.env.VITE_API_BASE_URL as string | undefined) ?? 'http://localhost:8000'

function headers(): HeadersInit {
  const h: Record<string, string> = { Accept: 'application/json' }
  const token = (import.meta.env.VITE_ADMIN_BEARER as string | undefined)?.trim()
  if (token) {
    h.Authorization = `Bearer ${token}`
  }
  return h
}

export async function adminGet<T>(path: string): Promise<T> {
  const res = await fetch(`${base.replace(/\/$/, '')}${path}`, { headers: headers() })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`${res.status} ${text}`)
  }
  return res.json() as Promise<T>
}

export function apiBase(): string {
  return base.replace(/\/$/, '')
}
