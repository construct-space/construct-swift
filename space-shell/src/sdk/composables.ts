/**
 * Faithful standalone ports of construct-app's SDK composables, backed by
 * window.construct + the live backend. Return shapes match the host so space
 * code behaves identically.
 */
import { ref, reactive, computed, onMounted, onUnmounted, type Ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import * as DateFns from 'date-fns'
import { marked } from 'marked'
import DOMPurify from 'dompurify'
import { api, rt, spaceId } from './runtime'
import { orgState, fetchOrgAll, useAuthStore } from './stores'

// ─── Breadcrumb ──────────────────────────────────────────────────────────────
export interface Breadcrumb { label: string; icon?: string; iconColor?: string; to?: string; options?: { label: string; to: string }[] }
const breadcrumbTrail: Ref<Breadcrumb[]> = ref([])
/** The breadcrumb trail rendered into the toolbar row (#toolbar-left). */
export const toolbarBreadcrumbs: Ref<Breadcrumb[]> = ref([])
const toolbarActions: Ref<unknown[]> = ref([])
const toolbarPageItems: Ref<unknown[]> = ref([])
const searchState = reactive<{ placeholder: string; handler: ((q: string) => void) | null }>({ placeholder: '', handler: null })

export function useBreadcrumb() {
  const trail = computed(() => breadcrumbTrail.value)
  const sync = () => { toolbarBreadcrumbs.value = breadcrumbTrail.value }
  return {
    trail,
    set: (items: Breadcrumb[]) => { breadcrumbTrail.value = [...items]; sync() },
    push: (item: Breadcrumb) => { breadcrumbTrail.value = [...breadcrumbTrail.value, item]; sync() },
    pop: () => { const n = [...breadcrumbTrail.value]; const l = n.pop(); breadcrumbTrail.value = n; sync(); return l },
    clear: () => { breadcrumbTrail.value = []; sync() },
  }
}

// ─── Toolbar ─────────────────────────────────────────────────────────────────
export function useToolbar() {
  return {
    breadcrumbs: computed(() => toolbarBreadcrumbs.value),
    toolbarItems: computed(() => toolbarPageItems.value),
    bottomToolbarItems: computed(() => [] as unknown[]),
    searchPlaceholder: computed(() => searchState.placeholder),
    hasSearchHandler: computed(() => !!searchState.handler),
    setBreadcrumbs: (b: Breadcrumb[]) => { toolbarBreadcrumbs.value = b ?? [] },
    setPageItems: (items: unknown[]) => { toolbarPageItems.value = items ?? [] },
    clearPageItems: () => { toolbarPageItems.value = [] },
    setSearch: (placeholder: string, handler: (q: string) => void) => { searchState.placeholder = placeholder; searchState.handler = handler },
    executeSearch: (q: string) => { searchState.handler?.(q) },
    registerItem: () => {},
    setActions: (a: unknown[]) => { toolbarActions.value = a ?? [] },
    initToolbar: async () => {},
    clearToolbar: () => { toolbarBreadcrumbs.value = []; toolbarPageItems.value = [] },
  }
}

// ─── Sidebar (reactive state holder) ────────────────────────────────────────
const sidebarState = reactive({ panel: 'main', mainItems: [] as unknown[], bottomItems: [] as unknown[], spaceItems: [] as unknown[] })
export function useSidebar() {
  return {
    state: sidebarState,
    setPanel: (p: string) => { sidebarState.panel = p },
    setMainItems: (items: unknown[], bottom: unknown[] = []) => { sidebarState.mainItems = items; sidebarState.bottomItems = bottom },
    enterSpace: () => {}, exitSpace: () => {},
    setSpaceAccounts: (items: unknown[]) => { sidebarState.spaceItems = items },
    enterProject: () => {}, exitProject: () => {},
  }
}

// ─── Navigator ───────────────────────────────────────────────────────────────
function normPath(p: string): string { return '/' + String(p).replace(/^\/+/, '') }
export function useNavigator() {
  const router = useRouter()
  const route = useRoute()
  return {
    current: computed(() => ({ path: route.path, params: route.params, query: route.query })),
    params: computed(() => route.params as Record<string, string>),
    query: computed(() => route.query as Record<string, string>),
    arguments: computed(() => route.query),
    to: <T = unknown>(path: string) => router.push(normPath(path)) as Promise<T | undefined>,
    off: (path: string) => router.replace(normPath(path)),
    offAll: (path: string) => router.replace(normPath(path)),
    back: () => router.back(),
    forward: () => router.forward(),
    go: (d: number) => router.go(d),
    isCurrent: (path: string) => route.path === normPath(path),
    until: () => {},
  }
}

// ─── Date format ─────────────────────────────────────────────────────────────
export function useDateFormat() {
  const toDate = (d: string | Date | null | undefined) => d == null ? null : (typeof d === 'string' || typeof d === 'number' ? new Date(d) : d)
  const fmt = (d: string | Date | null | undefined, f = 'd MMM yyyy') => { const dd = toDate(d); if (!dd) return ''; try { return DateFns.format(dd, f) } catch { return String(d) } }
  return {
    formatDate: fmt,
    formatDateShort: (d: string | Date | null | undefined) => fmt(d, 'd MMM yyyy'),
    formatDateNoYear: (d: string | Date | null | undefined) => fmt(d, 'd MMMM'),
    formatDateTime: (d: string | Date | null | undefined) => fmt(d, 'd MMMM yyyy, HH:mm'),
    formatDateRange: (a: string | Date | null | undefined, b: string | Date | null | undefined) => `${fmt(a)} – ${fmt(b)}`,
  }
}

// ─── Markdown ────────────────────────────────────────────────────────────────
export function useMarkdown() {
  const render = (content: string) => DOMPurify.sanitize(marked.parse(content ?? '', { async: false }) as string)
  return {
    renderMarkdown: render,
    renderStreamingMarkdown: render,
    renderMarkdownParts: (c: string) => [{ key: '0', html: render(c) }],
    renderStreamingMarkdownParts: (c: string) => [{ key: '0', html: render(c) }],
    initModules: async () => {},
  }
}
export const renderMarkdown = (c: string) => DOMPurify.sanitize(marked.parse(c ?? '', { async: false }) as string)
export const renderStreamingMarkdown = renderMarkdown

// ─── Notification ────────────────────────────────────────────────────────────
interface Notification { id: string; title: string; description?: string; color?: string; duration?: number }
const notifications: Ref<Notification[]> = ref([])
let notifSeq = 0
function addNotification(n: Omit<Notification, 'id'>): string {
  const id = `n${++notifSeq}`
  notifications.value = [...notifications.value, { ...n, id }]
  const dur = n.duration ?? 5000
  if (dur > 0) setTimeout(() => removeNotification(id), dur)
  return id
}
function removeNotification(id: string) { notifications.value = notifications.value.filter(n => n.id !== id) }
const toastMethod = (color: string) => (title: string, description?: string) => addNotification({ title, description, color })

export function useNotification() {
  const send = (input: { title: string; body?: string; type?: string; link?: string; data?: Record<string, unknown> }) =>
    api('POST', '/api/notifications/self', input)
  return {
    notifications, add: addNotification, remove: removeNotification,
    clear: () => { notifications.value = [] },
    notification: { add: addNotification, remove: removeNotification },
    send,
    success: toastMethod('success'), error: toastMethod('error'),
    warning: toastMethod('warning'), info: toastMethod('info'),
  }
}

export function useToast() {
  const toast = {
    success: toastMethod('success'), error: toastMethod('error'),
    warning: toastMethod('warning'), info: toastMethod('info'),
  }
  return { ...useNotification(), ...toast, toast }
}

// ─── Space context bus (mirrors spaceContextBus) ────────────────────────────
export interface SpaceContextPayload { spaceId: string; type: string; summary?: Record<string, unknown>; timestamp?: number }
const ctxLatest = new Map<string, SpaceContextPayload>()
const ctxSubs = new Map<string, Set<(p: SpaceContextPayload) => void>>()
const ctxHandlers = new Map<string, (req: unknown) => unknown>()
const automationProviders = new Map<string, unknown>()

export function publishSpaceContext(payload: SpaceContextPayload): void {
  ctxLatest.set(payload.type, payload)
  ctxSubs.get(payload.type)?.forEach(cb => { try { cb(payload) } catch { /* ignore */ } })
  // Also surface to the native host bridge.
  try { (rt() as { context?: { publish?: (t: string, s?: unknown) => void } }).context?.publish?.(payload.type, payload.summary) } catch { /* ignore */ }
}
export function subscribeSpaceContext(type: string, cb: (p: SpaceContextPayload) => void): () => void {
  if (!ctxSubs.has(type)) ctxSubs.set(type, new Set())
  ctxSubs.get(type)!.add(cb)
  return () => ctxSubs.get(type)?.delete(cb)
}
export function getLatestSpaceContext(type: string): SpaceContextPayload | undefined { return ctxLatest.get(type) }
export function registerContextHandler(spaceId: string, handler: (req: unknown) => unknown): () => void {
  ctxHandlers.set(spaceId, handler)
  return () => ctxHandlers.delete(spaceId)
}
export function registerAutomationProvider(spaceId: string, provider: unknown): () => void {
  automationProviders.set(spaceId, provider)
  return () => automationProviders.delete(spaceId)
}
export function getAutomationProvider(spaceId: string): unknown { return automationProviders.get(spaceId) }
export function requestSpaceData(spaceId: string, request: unknown): unknown { return ctxHandlers.get(spaceId)?.(request) }

// ─── Storage (gateway-proxied object storage) ───────────────────────────────
function storageKey(path: string): string {
  if (path.startsWith('orgs/') || path.startsWith('org/')) return path
  return `${spaceId()}/${path.replace(/^\/+/, '')}`
}
export function useStorage() {
  const loading = ref(false)
  const error = ref<string | null>(null)
  return {
    loading, error,
    upload: async (file: Blob, opts?: { path?: string; contentType?: string }) => {
      loading.value = true
      try {
        const form = new FormData()
        form.append('file', file)
        form.append('key', storageKey(opts?.path ?? `${Date.now()}`))
        const token = await rt().auth?.getAccessToken()
        const res = await fetch(`${rt().config?.apiBase}/api/storage/upload`, {
          method: 'POST', body: form,
          headers: token ? { Authorization: `Bearer ${token}` } : {},
        })
        if (!res.ok) throw new Error(`Upload failed (${res.status})`)
        return await res.json()
      } finally { loading.value = false }
    },
    download: async (path: string) => {
      const token = await rt().auth?.getAccessToken()
      const res = await fetch(`${rt().config?.apiBase}/api/storage/${storageKey(path)}?mode=stream`, {
        headers: token ? { Authorization: `Bearer ${token}` } : {},
      })
      if (!res.ok) throw new Error(`Download failed (${res.status})`)
      return await res.blob()
    },
    delete: (path: string) => api('DELETE', `/api/storage/${storageKey(path)}`),
    list: (opts?: { prefix?: string }) => api('GET', `/api/storage/list?prefix=${encodeURIComponent(opts?.prefix ?? spaceId())}`),
    exists: async (path: string) => { try { await api('HEAD', `/api/storage/${storageKey(path)}`); return true } catch { return false } },
  }
}

// ─── Scheduler ───────────────────────────────────────────────────────────────
export function useScheduler() {
  const base = '/api/source/scheduler/tasks'
  return {
    create: (input: unknown) => api('POST', base, input),
    list: (filter?: Record<string, string>) => api('GET', `${base}${filter ? '?' + new URLSearchParams(filter).toString() : ''}`),
    get: (id: string) => api('GET', `${base}/${id}`),
    update: (id: string, patch: unknown) => api('PATCH', `${base}/${id}`, patch),
    toggle: (id: string, enabled: boolean) => api('PATCH', `${base}/${id}`, { enabled }),
    cancel: (id: string) => api('DELETE', `${base}/${id}`),
    runNow: (id: string) => api('POST', `${base}/${id}/run`, {}),
    claim: (id: string, input: unknown) => api('POST', `${base}/${id}/claim`, input),
    report: (id: string, input: unknown) => api('POST', `${base}/${id}/report`, input),
    onFire: () => () => {},
  }
}

// ─── HTTP (spaces calling their own APIs; CORS-free via the bridge later) ────
export function useHttp() {
  const doFetch = async <T>(method: string, url: string, data?: unknown, config?: { headers?: Record<string, string> }): Promise<T> => {
    const res = await fetch(url, {
      method,
      headers: { ...(data !== undefined ? { 'Content-Type': 'application/json' } : {}), ...(config?.headers ?? {}) },
      body: data !== undefined ? JSON.stringify(data) : undefined,
    })
    const text = await res.text()
    try { return JSON.parse(text) as T } catch { return text as unknown as T }
  }
  return {
    get: <T>(url: string, c?: { headers?: Record<string, string> }) => doFetch<T>('GET', url, undefined, c),
    post: <T>(url: string, data?: unknown, c?: { headers?: Record<string, string> }) => doFetch<T>('POST', url, data, c),
    put: <T>(url: string, data?: unknown, c?: { headers?: Record<string, string> }) => doFetch<T>('PUT', url, data, c),
    patch: <T>(url: string, data?: unknown, c?: { headers?: Record<string, string> }) => doFetch<T>('PATCH', url, data, c),
    delete: <T>(url: string, c?: { headers?: Record<string, string> }) => doFetch<T>('DELETE', url, undefined, c),
    fetch: (url: string, init?: RequestInit) => fetch(url, init),
    isHttpError: (e: unknown) => e instanceof Error,
  }
}

// ─── Download / Export / Import ─────────────────────────────────────────────
export function useDownload() {
  const save = async (data: Blob | string | Uint8Array, opts: { filename: string; mimeType?: string }) => {
    const blob = data instanceof Blob ? data : new Blob([data as BlobPart], { type: opts.mimeType ?? 'application/octet-stream' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = opts.filename; a.click()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
  }
  return { save, saveUrl: async (url: string, opts: { filename: string }) => { const a = document.createElement('a'); a.href = url; a.download = opts.filename; a.click() } }
}
const DATA_FORMATS = [{ id: 'json', label: 'JSON', ext: 'json' }, { id: 'csv', label: 'CSV', ext: 'csv' }]
export function useExport() {
  const { save } = useDownload()
  const toCSV = (rows: Record<string, unknown>[]) => {
    if (!rows.length) return ''
    const cols = Object.keys(rows[0])
    const esc = (v: unknown) => `"${String(v ?? '').replace(/"/g, '""')}"`
    return [cols.join(','), ...rows.map(r => cols.map(c => esc(r[c])).join(','))].join('\n')
  }
  const generate = async (rows: Record<string, unknown>[], opts: { format: string }) =>
    opts.format === 'csv' ? toCSV(rows) : JSON.stringify(rows, null, 2)
  return {
    formats: DATA_FORMATS,
    generate,
    save: async (rows: Record<string, unknown>[], opts: { format: string; filename: string }) => save(await generate(rows, opts), { filename: opts.filename }),
  }
}
export function useImport() {
  const parse = async <T = Record<string, unknown>>(input: string | File | Blob, opts?: { format?: string }): Promise<T[]> => {
    const text = typeof input === 'string' ? input : await input.text()
    if (opts?.format === 'csv' || (typeof input !== 'string' && (input as File).name?.endsWith('.csv'))) {
      const [head, ...lines] = text.split(/\r?\n/).filter(Boolean)
      const cols = head.split(',').map(c => c.replace(/^"|"$/g, ''))
      return lines.map(l => { const vals = l.split(','); const o: Record<string, string> = {}; cols.forEach((c, i) => o[c] = (vals[i] ?? '').replace(/^"|"$/g, '')); return o as T }) as T[]
    }
    return JSON.parse(text) as T[]
  }
  return { formats: DATA_FORMATS, parse }
}

// ─── Org family ──────────────────────────────────────────────────────────────
export function useOrg() {
  const auth = useAuthStore()
  return {
    orgId: computed(() => auth.orgId),
    orgName: computed(() => (orgState.currentOrg?.name as string) ?? null),
    currentOrg: computed(() => orgState.currentOrg),
    isOrg: computed(() => auth.scope === 'org'),
    roles: computed(() => auth.roles),
    isAdmin: computed(() => auth.isOrgAdmin),
    loading: computed(() => orgState.loading),
    refresh: () => fetchOrgAll(),
  }
}
function ensureOrg() { if (!orgState.hydrated && !orgState.loading) void fetchOrgAll() }
export function useOrgMembers() {
  ensureOrg()
  return {
    members: computed(() => orgState.members),
    loading: computed(() => orgState.loading),
    memberCount: computed(() => orgState.members.length),
    byId: (id: string) => orgState.members.find(m => m.id === id) ?? null,
    byUserId: (uid: string) => orgState.members.find(m => m.user_id === uid) ?? null,
    refresh: () => fetchOrgAll(),
  }
}
export function useOrgTeams() {
  ensureOrg()
  return {
    teams: computed(() => orgState.teams),
    loading: computed(() => orgState.loading),
    teamCount: computed(() => orgState.teams.length),
    byId: (id: string) => orgState.teams.find(t => t.id === id) ?? null,
    membersOf: () => [], teamsOf: () => [],
    refresh: () => fetchOrgAll(),
  }
}
export function useOrgDepartments() {
  ensureOrg()
  return {
    departments: computed(() => orgState.departments),
    loading: computed(() => orgState.loading),
    departmentCount: computed(() => orgState.departments.length),
    byId: (id: string) => orgState.departments.find(d => d.id === id) ?? null,
    ofMember: () => null, membersOf: () => [],
    refresh: () => fetchOrgAll(),
  }
}
export function useOrgRoles() {
  ensureOrg()
  const matches = (perm: string, granted: string) => granted === '*' || granted === perm || (granted.endsWith('.*') && perm.startsWith(granted.slice(0, -1)))
  return {
    roles: computed(() => orgState.roles),
    loading: computed(() => orgState.loading),
    byId: (id: string) => orgState.roles.find(r => r.id === id) ?? null,
    byName: (n: string) => orgState.roles.find(r => r.name === n) ?? null,
    ofMember: () => null,
    can: (perm: string) => orgState.roles.some(r => (r.permissions as string[] | undefined)?.some(p => matches(perm, p))),
    refresh: () => fetchOrgAll(),
  }
}

// ─── Authorization / Access (personal mode: permissive) ──────────────────────
export function useAuthorization() {
  return {
    can: async () => true, canSync: () => true, hasPermission: () => true,
    canMultiple: async () => ({}), canAny: async () => true, canAll: async () => true,
    useCanReactive: () => computed(() => true), usePermissionReactive: () => computed(() => true),
    initialize: async () => {}, clearCache: () => {},
    authorizationStore: null, roles: computed(() => []), roleOptions: computed(() => []),
    isLoadingRoles: computed(() => false), isLoadingUserPermissions: computed(() => false),
  }
}
export function useAccess<T = unknown>() {
  const base = '/api/source/access'
  return {
    can: () => ref(true), canSync: () => true,
    filter: (_a: string, items: T[]) => ref(items), decide: () => ref(new Map()),
    members: () => ref([]), isOrgWide: () => ref(false), isRestricted: () => ref(false),
    hasAccess: () => ref(true), roleOf: () => ref(null), hasRoleAtLeast: () => ref(true),
    grant: (resource: unknown, userId: string, role: string) => api('POST', `${base}/grant`, { resource, userId, role }),
    revoke: (resource: unknown, userId: string) => api('POST', `${base}/revoke`, { resource, userId }),
    setRole: (resource: unknown, userId: string, role: string) => api('POST', `${base}/grant`, { resource, userId, role }),
    openToOrg: (resource: unknown) => api('POST', `${base}/open`, { resource }),
    transferOwnership: (resource: unknown, toUserId: string) => api('POST', `${base}/transfer`, { resource, toUserId }),
  }
}

// ─── Config / runtime ────────────────────────────────────────────────────────
export function useConstructConfig() {
  const r = rt()
  return {
    graphUrl: r.config?.graphUrl ?? '',
    apiBase: r.config?.apiBase ?? '',
    spacesRegistryUrl: '', accountsUrl: r.config?.apiBase ?? '', freepikApiKey: '',
  }
}
export function getConstructRuntime() { return rt() }

// ─── Theme ───────────────────────────────────────────────────────────────────
const themeRef = ref<'light' | 'dark'>(window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light')
export function useAppTheme() {
  return {
    theme: computed(() => themeRef.value),
    isDark: computed(() => themeRef.value === 'dark'),
    setTheme: (t: 'light' | 'dark') => { themeRef.value = t },
    toggle: () => { themeRef.value = themeRef.value === 'dark' ? 'light' : 'dark' },
  }
}

// ─── Presence / media (reactive holders) ────────────────────────────────────
const presenceRef = ref<string>(localStorage.getItem('construct.presence-status.v1') ?? 'online')
export function usePresenceStatus() {
  return { status: presenceRef, setStatus: (s: string) => { presenceRef.value = s; localStorage.setItem('construct.presence-status.v1', s) } }
}
const mediaState = reactive({ track: null as unknown, isPlaying: false, isBuffering: false, position: 0, duration: 0 })
export function useMediaSession() {
  return {
    state: mediaState, capabilities: { skipForward: true, skipBack: true, seek: true },
    setTrack: (t: unknown) => { mediaState.track = t }, publish: (p: Record<string, unknown>) => Object.assign(mediaState, p),
    registerControls: () => {}, clear: () => { mediaState.track = null },
    toggle: () => { mediaState.isPlaying = !mediaState.isPlaying }, play: () => { mediaState.isPlaying = true }, pause: () => { mediaState.isPlaying = false },
    skipForward: () => {}, skipBack: () => {}, stop: () => { mediaState.isPlaying = false }, seek: () => {},
  }
}

// ─── Space shortcuts ─────────────────────────────────────────────────────────
export function useSpaceShortcuts(shortcuts: { key: string; handler: () => void }[]) {
  const onKey = (e: KeyboardEvent) => {
    for (const s of shortcuts) if (s.key.toLowerCase() === e.key.toLowerCase()) { e.preventDefault(); s.handler() }
  }
  onMounted(() => window.addEventListener('keydown', onKey))
  onUnmounted(() => window.removeEventListener('keydown', onKey))
}

// Re-export router hooks the SDK surfaces.
export { useRoute, useRouter }
