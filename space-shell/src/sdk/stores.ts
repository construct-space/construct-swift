/**
 * Reactive singleton stores mirroring construct-app's Pinia stores' read
 * surface (the parts spaces consume). Hydrated lazily from window.construct +
 * the live backend. Property access on the returned object is reactive, so
 * `useAuthStore().user` etc. behave like the host store for space code.
 */
import { reactive } from 'vue'
import { api, rt } from './runtime'

// ─── auth ──────────────────────────────────────────────────────────────────
interface AuthUser { id: string; email: string; name?: string; avatar?: string }
const authState = reactive({
  user: null as AuthUser | null,
  token: null as string | null,
  oauthToken: null as string | null,
  orgId: null as string | null,
  scope: 'user' as 'user' | 'org',
  roles: [] as string[],
  isAuthenticated: false,
  personalDeveloper: false,
  orgDeveloper: false,
  _hydrated: false,
})

async function hydrateAuth(): Promise<void> {
  if (authState._hydrated) return
  authState._hydrated = true
  const r = rt()
  authState.token = (await r.auth?.getAccessToken()) ?? null
  authState.oauthToken = authState.token
  authState.isAuthenticated = !!authState.token
  authState.orgId = r.org?.id ?? null
  authState.scope = (r.scope as 'user' | 'org') ?? 'user'
  try {
    const me = await api<{ uuid?: string; id?: string; email?: string; name?: string; avatar_url?: string }>('GET', '/api/accounts/me')
    authState.user = {
      id: me.uuid ?? me.id ?? r.auth?.getUserId() ?? '',
      email: me.email ?? '',
      name: me.name,
      avatar: me.avatar_url,
    }
  } catch {
    const id = r.auth?.getUserId() ?? ''
    if (id) authState.user = { id, email: '' }
  }
}

export function useAuthStore() {
  void hydrateAuth()
  return Object.assign(authState, {
    get currentUser() { return authState.user },
    get userName() { return authState.user?.name ?? authState.user?.email ?? '' },
    get userEmail() { return authState.user?.email ?? '' },
    get userAvatar() { return authState.user?.avatar ?? null },
    get isDeveloper() {
      return authState.scope === 'org'
        ? authState.orgDeveloper || authState.roles.includes('developer')
        : authState.personalDeveloper
    },
    get isOrgAdmin() {
      return authState.scope === 'org' && (authState.roles.includes('owner') || authState.roles.includes('admin'))
    },
    getAccessToken: () => rt().auth?.getAccessToken() ?? Promise.resolve(null),
  })
}

// ─── preferences ─────────────────────────────────────────────────────────────
const prefsState = reactive({
  preferences: {} as Record<string, unknown>,
  loading: false,
  initialized: false,
  _hydrated: false,
})

async function hydratePrefs(): Promise<void> {
  if (prefsState._hydrated) return
  prefsState._hydrated = true
  try {
    const data = await api<Record<string, unknown>>('GET', '/api/preferences')
    prefsState.preferences = data ?? {}
    prefsState.initialized = true
  } catch { /* defaults */ }
}

export function usePreferencesStore() {
  void hydratePrefs()
  const get = <T>(key: string, def: T): T => (prefsState.preferences[key] as T) ?? def
  return Object.assign(prefsState, {
    get,
    get theme() { return get('theme', 'dark') },
    get sidebarWidth() { return get('sidebarWidth', 280) },
    get sidebarCollapsed() { return get('sidebarCollapsed', false) },
    get toolbarCollapsed() { return get('toolbarCollapsed', false) },
    get toolbarPosition() { return get('toolbarPosition', 'top') },
    get editorSettings() { return get('editorSettings', {}) },
    async setPreference<T>(key: string, value: T) {
      prefsState.preferences[key] = value
      try { await api('PUT', `/api/preferences/${encodeURIComponent(key)}`, { value }); return { success: true } }
      catch (e) { return { success: false, error: String(e) } }
    },
    async fetchPreferences() { prefsState._hydrated = false; await hydratePrefs(); return prefsState.preferences },
  })
}

// ─── settings ────────────────────────────────────────────────────────────────
const settingsState = reactive({ settings: [] as Record<string, unknown>[], isLoading: false, _hydrated: false })
export function useSettingsStore() {
  if (!settingsState._hydrated) {
    settingsState._hydrated = true
    api<Record<string, unknown>[]>('GET', '/api/settings').then(s => { settingsState.settings = s ?? [] }).catch(() => {})
  }
  const byKey = (k: string) => settingsState.settings.find(s => s.setting_key === k)
  return Object.assign(settingsState, {
    getByKey: byKey,
    getByGroup: (g: string) => settingsState.settings.filter(s => s.group === g),
    get aiEnabled() { return (byKey('ai_enabled')?.value_bool as boolean) ?? true },
    get timezone() { return (byKey('timezone')?.value_string as string) ?? 'UTC' },
  })
}

// ─── project (minimal — current project from runtime context) ───────────────
const projectState = reactive({
  currentProject: null as { id: string; name?: string } | null,
  projects: [] as { id: string; name?: string }[],
})
export function useProjectStore() {
  const pid = rt().project?.id
  if (pid && projectState.currentProject?.id !== pid) projectState.currentProject = { id: pid }
  return Object.assign(projectState, {
    get hasProject() { return !!projectState.currentProject },
    getProjectById: (id: string) => projectState.projects.find(p => p.id === id) ?? null,
  })
}
export const usePanelsStore = useProjectStore

// ─── org (hydrated from /api/source/org/*) ──────────────────────────────────
export const orgState = reactive({
  currentOrg: null as Record<string, unknown> | null,
  members: [] as Record<string, unknown>[],
  teams: [] as Record<string, unknown>[],
  departments: [] as Record<string, unknown>[],
  roles: [] as Record<string, unknown>[],
  permissions: [] as Record<string, unknown>[],
  loading: false,
  hydrated: false,
})

export async function fetchOrgAll(): Promise<void> {
  if (orgState.loading) return
  orgState.loading = true
  try {
    const [members, teams, departments, roles] = await Promise.all([
      api<Record<string, unknown>[]>('GET', '/api/source/org/members').catch(() => []),
      api<Record<string, unknown>[]>('GET', '/api/source/org/teams').catch(() => []),
      api<Record<string, unknown>[]>('GET', '/api/source/org/departments').catch(() => []),
      api<Record<string, unknown>[]>('GET', '/api/source/org/roles').catch(() => []),
    ])
    orgState.members = members ?? []
    orgState.teams = teams ?? []
    orgState.departments = departments ?? []
    orgState.roles = roles ?? []
    orgState.hydrated = true
  } finally {
    orgState.loading = false
  }
}
