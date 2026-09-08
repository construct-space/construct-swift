/**
 * Shared access to the native-injected `window.construct` runtime context and a
 * bearer-authenticated fetch helper used by the ported SDK composables.
 */
export interface ConstructRuntime {
  config?: { graphUrl?: string; apiBase?: string }
  auth?: { getAccessToken(): Promise<string | null>; getUserId(): string | null }
  space?: { id: string }
  project?: { id?: string }
  org?: { id?: string; dataResidency?: string } | null
  scope?: string
  storage?: { get(k: string): Promise<string | null>; set(k: string, v: string): Promise<void>; remove(k: string): Promise<void> }
  shell?: { openUrl(u: string): Promise<void> }
  graph?: { query<T>(q: string, v?: Record<string, unknown>): Promise<T> }
}

export function rt(): ConstructRuntime {
  return ((window as unknown as { construct?: ConstructRuntime }).construct) ?? {}
}

export function apiBase(): string {
  return (rt().config?.apiBase ?? '').replace(/\/+$/, '')
}

export function spaceId(): string {
  return rt().space?.id ?? ''
}

/** Bearer-authenticated JSON fetch against the gateway. */
export async function api<T = unknown>(
  method: string,
  path: string,
  body?: unknown,
  extraHeaders?: Record<string, string>,
): Promise<T> {
  const token = (await rt().auth?.getAccessToken()) ?? null
  const headers: Record<string, string> = {
    'Accept': 'application/json',
    ...(extraHeaders ?? {}),
  }
  if (token) headers['Authorization'] = `Bearer ${token}`
  if (body !== undefined) headers['Content-Type'] = 'application/json'

  const url = path.startsWith('http') ? path : `${apiBase()}${path.startsWith('/') ? '' : '/'}${path}`
  const res = await fetch(url, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  })
  const text = await res.text()
  let parsed: unknown = undefined
  try { parsed = text ? JSON.parse(text) : undefined } catch { /* non-json */ }
  if (!res.ok) {
    const msg = (parsed as { error?: string; message?: string })?.error
      || (parsed as { message?: string })?.message
      || `Request failed (${res.status})`
    throw new Error(msg)
  }
  return parsed as T
}
