/**
 * Mounts a loaded space bundle's pages, replicating construct-app's
 * DynamicSpacePage routing: exact-path match first, then parameterized
 * (`:id` / `[id]`) routes, with route params passed as component props, and
 * CSS scoped to `[data-construct-space="<id>"]`.
 */
import { createApp, h, ref, markRaw, computed, defineComponent, onMounted, Teleport } from 'vue'
import { createPinia } from 'pinia'
import { createRouter, createMemoryHistory, useRoute, useRouter } from 'vue-router'
import { Icon as UIIcon } from '@construct-space/ui'
import { toolbarBreadcrumbs } from './sdk/composables'

export interface SpaceBoot {
  id: string
  /** Initial in-space path, e.g. "" or "places". */
  initialPath?: string
}

interface SpaceGlobal {
  pages: Record<string, unknown>
  components?: Record<string, unknown>
  widgets?: Record<string, Record<string, unknown>>
  init?: () => void
}

/** Mirror of construct-app `toGlobalKey`. */
function toGlobalKey(spaceId: string): string {
  return `__CONSTRUCT_SPACE_${spaceId.replace(/[^a-zA-Z0-9]/g, '_').toUpperCase()}`
}

/** The in-space path (no leading slash) from a router path. */
function currentPath(routePath: string): string {
  return routePath.replace(/^\/+/, '')
}

/** Matches a request path against a page key pattern (`:id` or `[id]`),
 *  returning extracted params, or null. Mirrors the host's matchRoutePattern. */
function matchPattern(path: string, pattern: string): Record<string, string> | null {
  const pp = pattern.replace(/\[([^\]]+)\]/g, ':$1')
  const pSeg = pp.split('/').filter(Boolean)
  const aSeg = path.split('/').filter(Boolean)
  if (pSeg.length !== aSeg.length) return null
  const params: Record<string, string> = {}
  for (let i = 0; i < pSeg.length; i++) {
    if (pSeg[i].startsWith(':')) params[pSeg[i].slice(1)] = decodeURIComponent(aSeg[i])
    else if (pSeg[i] !== aSeg[i]) return null
  }
  return params
}

/** Resolves which page component renders for a path: exact match first, then
 *  parameterized patterns. Mirrors DynamicSpacePage's currentPage logic. */
function resolvePage(pages: Record<string, unknown>, path: string): { component: unknown; params: Record<string, string> } {
  if (pages[path]) return { component: pages[path], params: {} }
  for (const key of Object.keys(pages)) {
    if (!key.includes(':') && !key.includes('[')) continue
    const params = matchPattern(path, key)
    if (params) return { component: pages[key], params }
  }
  return { component: null, params: {} }
}

async function injectSpaceCss(spaceId: string): Promise<void> {
  // Each space runs in its OWN dedicated webview (no host chrome to collide
  // with), so the space's stylesheet is injected RAW — scoping it would only
  // risk mangling its Tailwind output.
  try {
    const res = await fetch(`space://${spaceId}/style.css`)
    if (!res.ok) return
    const css = await res.text()
    const style = document.createElement('style')
    style.setAttribute('data-space', spaceId)
    style.textContent = css
    document.head.appendChild(style)
  } catch {
    // No stylesheet — fine.
  }
}

let mounted = false

function hasToolbarLeft(): boolean {
  return typeof document !== 'undefined' && !!document.querySelector('#toolbar-left')
}

/** Renders the space breadcrumb trail ("Boards › Bugs ▾") with an optional
 *  per-crumb dropdown of sibling destinations, mirroring the host toolbar. */
const BreadcrumbBar = defineComponent({
  name: 'BreadcrumbBar',
  setup() {
    const router = useRouter()
    const openIdx = ref(-1)
    const go = (to?: string) => { if (to) router.push('/' + to.replace(/^\/+/, '')); openIdx.value = -1 }
    return () => {
      const crumbs = toolbarBreadcrumbs.value
      if (!crumbs.length) return null
      const nodes: unknown[] = []
      crumbs.forEach((c, i) => {
        if (i > 0) nodes.push(h('span', { style: 'opacity:0.4;font-size:13px' }, '›'))
        const last = i === crumbs.length - 1
        const clickable = !!(c.to || c.options?.length)
        const inner: unknown[] = []
        if (c.icon) inner.push(h(UIIcon, { name: c.icon, class: 'size-4', style: c.iconColor ? `color:${c.iconColor}` : '' }))
        inner.push(h('span', {
          style: `font-size:13px;font-weight:${last ? 600 : 400};white-space:nowrap`,
        }, c.label))
        if (c.options?.length) {
          inner.push(h('span', { style: 'opacity:0.5;font-size:10px' }, '▾'))
        }
        const crumbEl = h('span', {
          style: `display:inline-flex;align-items:center;gap:4px;cursor:${clickable ? 'pointer' : 'default'};padding:2px 4px;border-radius:6px`,
          onClick: () => {
            if (c.options?.length) openIdx.value = openIdx.value === i ? -1 : i
            else go(c.to)
          },
        }, inner)
        // Dropdown of sibling destinations.
        const menu = (c.options?.length && openIdx.value === i)
          ? h('div', {
              style: 'position:absolute;top:100%;left:0;margin-top:4px;min-width:180px;z-index:50;'
                + 'background:var(--app-surface,#fff);color:var(--app-foreground,#111);'
                + 'border:1px solid color-mix(in srgb,currentColor 12%,transparent);border-radius:10px;'
                + 'box-shadow:0 8px 24px rgba(0,0,0,0.18);padding:4px;',
            }, c.options.map(o => h('div', {
              style: 'padding:7px 10px;border-radius:7px;font-size:13px;cursor:pointer;white-space:nowrap',
              onMouseenter: (e: Event) => { (e.target as HTMLElement).style.background = 'color-mix(in srgb,currentColor 8%,transparent)' },
              onMouseleave: (e: Event) => { (e.target as HTMLElement).style.background = 'transparent' },
              onClick: () => go(o.to),
            }, o.label)))
          : null
        nodes.push(h('span', { style: 'position:relative;display:inline-flex;align-items:center' }, [crumbEl, menu].filter(Boolean)))
      })
      return h('div', { style: 'display:flex;align-items:center;gap:4px' }, nodes)
    }
  },
})

export async function mountSpace(boot: SpaceBoot): Promise<void> {
  if (mounted) return
  mounted = true

  const global = (window as unknown as Record<string, SpaceGlobal | undefined>)[toGlobalKey(boot.id)]
  if (!global || typeof global.pages !== 'object') {
    renderError(`Space "${boot.id}" did not export pages.`)
    return
  }

  if (typeof global.init === 'function') {
    try { global.init() } catch (e) { console.warn('[space-shell] init() failed', e) }
  }

  const pages = global.pages as Record<string, unknown>
  Object.keys(pages).forEach(k => { pages[k] = markRaw(pages[k] as object) })

  // Single catch-all route so vue-router (useRoute/useRouter) works for spaces,
  // while WE resolve which page component to render by path — exactly like the
  // host's DynamicSpacePage (`<component :is="currentPage" v-bind="params">`),
  // rather than registering each page as its own route component.
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/:pathMatch(.*)*', name: 'space', component: { render: () => null } }],
  })

  const Root = defineComponent({
    setup() {
      const route = useRoute()
      const resolved = computed(() => resolvePage(pages, currentPath(route.path)))
      return () => h('div', {
        'class': 'construct-space-root',
        'style': 'height:100%',
        'data-construct-space': boot.id,
      }, [
        // The space's breadcrumb trail, teleported into the toolbar row's left
        // region (matches the Tauri Toolbar3D breadcrumb).
        h(Teleport, { to: '#toolbar-left', disabled: !hasToolbarLeft() }, [h(BreadcrumbBar)]),
        resolved.value.component
          ? h(resolved.value.component as ReturnType<typeof defineComponent>, {
              key: route.path,
              projectId: undefined,
              ...resolved.value.params,
            })
          : h('div', { style: 'padding:24px;font-family:system-ui' }, 'Page not found'),
      ])
    },
  })

  const app = createApp(Root)
  // Surface which component/hook errors, instead of an opaque vue-internal trace.
  app.config.errorHandler = (err, instance, info) => {
    const inst = instance as unknown as { type?: Record<string, unknown> } | null
    const name = (inst?.type?.name as string) || (inst?.type?.__name as string) || 'anon'
    console.error(`[space-shell] vue error in <${name}> (${info}):`, err)
  }
  app.use(createPinia())
  app.use(router)

  // Install @construct-space/ui as a plugin if it exposes one — its components
  // may rely on plugin-time setup (directives/provides) that's otherwise absent
  // under a fresh per-space app instance.
  try {
    const ui = (window.__CONSTRUCT__ as Record<string, unknown>)['@construct-space/ui'] as { default?: unknown; install?: unknown }
    const plugin = (ui?.default ?? ui) as { install?: unknown }
    if (plugin && typeof plugin.install === 'function') {
      app.use(plugin as Parameters<typeof app.use>[0])
    }
  } catch (e) {
    console.warn('[space-shell] UI plugin install skipped:', e)
  }

  // Global components the host registers (main.ts) that spaces use without
  // importing — `<Icon name="...">` is pervasive; absence makes the icon vnode
  // never mount and crashes the next update with the emitsOptions null error.
  app.component('Icon', UIIcon as ReturnType<typeof defineComponent>)
  app.component('Notification', defineComponent({
    name: 'Notification',
    setup: (_p, { slots }) => () => h('div', { class: 'construct-notification' }, slots.default ? slots.default() : []),
  }))

  const initial = '/' + (boot.initialPath ?? '').replace(/^\/+/, '')
  await router.replace(initial).catch(() => router.replace('/'))
  app.mount('#app')
}

function renderError(message: string): void {
  const el = document.getElementById('app')
  if (el) el.innerHTML = `<div style="padding:24px;color:#b00;font-family:system-ui">${message}</div>`
}

// ─── Widget dashboard (Home) ────────────────────────────────────────────────

export interface WidgetPlacement { spaceId: string; widgetId: string; sizeKey: string }
export interface WidgetsBoot { widgets: WidgetPlacement[]; edit?: boolean }

/** Posts a home-edit action back to the native host (remove / resize / add). */
function postEdit(msg: Record<string, unknown>): void {
  try {
    const w = window as unknown as { webkit?: { messageHandlers?: { homeEdit?: { postMessage: (m: string) => void } } } }
    w.webkit?.messageHandlers?.homeEdit?.postMessage(JSON.stringify(msg))
  } catch { /* not in a host webview */ }
}

const loadedBundles = new Set<string>()
async function ensureBundle(spaceId: string): Promise<Record<string, unknown> | undefined> {
  const key = toGlobalKey(spaceId)
  const w = window as unknown as Record<string, Record<string, unknown> | undefined>
  if (w[key]) return w[key]
  try {
    const res = await fetch(`space://${spaceId}/app.iife.js`)
    if (!res.ok) return undefined
    const code = await res.text()
    ;(0, eval)(code) // assigns window[__CONSTRUCT_SPACE_<ID>]
    if (!loadedBundles.has(spaceId)) { loadedBundles.add(spaceId); await injectSpaceCss(spaceId) }
    return w[key]
  } catch { return undefined }
}

/** Maps a "WxH" size key to grid spans. */
function spanFor(sizeKey: string): { w: number; h: number } {
  const [w, h] = sizeKey.split('x').map(n => parseInt(n, 10) || 1)
  return { w, h }
}

/** Closest available size to `want` (by area), so a widget never renders a
 *  variant it doesn't define. */
function nearestSize(want: string, available: string[]): string {
  if (!available.length) return want
  const area = (s: string) => { const { w, h } = spanFor(s); return w * h }
  const target = area(want)
  return available.slice().sort((a, b) => Math.abs(area(a) - target) - Math.abs(area(b) - target))[0]
}

const WidgetCell = defineComponent({
  name: 'WidgetCell',
  props: { placement: { type: Object, required: true }, edit: { type: Boolean, default: false } },
  setup(props) {
    const comp = ref<unknown>(null)
    const error = ref('')
    // The size actually rendered — defaults to the requested one, but falls back
    // to a size the widget actually defines, and the grid span follows THIS so
    // the cell footprint matches the rendered variant (respect widget sizes).
    const effectiveSize = ref((props.placement as WidgetPlacement).sizeKey)
    onMounted(async () => {
      const p = props.placement as WidgetPlacement
      const g = await ensureBundle(p.spaceId)
      const widgets = g?.widgets as Record<string, Record<string, unknown>> | undefined
      const byId = widgets?.[p.widgetId]
      if (!byId) { error.value = `No widget ${p.widgetId}`; return }
      // Prefer the requested size; else the closest the widget defines.
      const available = Object.keys(byId)
      const sizeKey = byId[p.sizeKey] ? p.sizeKey : nearestSize(p.sizeKey, available)
      effectiveSize.value = sizeKey
      const chosen = byId[sizeKey]
      if (!chosen) { error.value = `No widget ${p.widgetId}`; return }
      // Bind the runtime's active space so the widget's graph queries hit its
      // own tenant (best-effort; shared global).
      const rt = (window as unknown as { construct?: { space?: { id: string } } }).construct
      if (rt?.space) rt.space.id = p.spaceId
      comp.value = markRaw(chosen as object)
    })
    return () => {
      const { w: colSpan, h: rowSpan } = spanFor(effectiveSize.value)
      const p = props.placement as WidgetPlacement
      const children: unknown[] = [
        comp.value
          ? h(comp.value as ReturnType<typeof defineComponent>)
          : h('div', { style: 'padding:12px;font-size:12px;opacity:0.6' }, error.value || '…'),
      ]
      if (props.edit) {
        // Dim + block interaction with the widget content, overlay controls.
        children.push(h('div', { style: 'position:absolute;inset:0;background:color-mix(in srgb,var(--app-canvas-bg) 35%,transparent);' }))
        children.push(h('button', {
          title: 'Remove',
          onClick: (e: Event) => { e.stopPropagation(); postEdit({ type: 'remove', spaceId: p.spaceId, widgetId: p.widgetId }) },
          style: editBtnStyle('top:6px;right:6px;'),
        }, '✕'))
        children.push(h('button', {
          title: 'Resize',
          onClick: (e: Event) => { e.stopPropagation(); postEdit({ type: 'resize', spaceId: p.spaceId, widgetId: p.widgetId }) },
          style: editBtnStyle('bottom:6px;right:6px;'),
        }, '⤡'))
      }
      return h('div', {
        class: 'construct-widget',
        'data-construct-space': p.spaceId,
        style: `grid-column: span ${colSpan}; grid-row: span ${rowSpan};overflow:hidden;position:relative;`
          + 'background:var(--app-card-bg,#fff);border:1px solid color-mix(in srgb,currentColor 8%,transparent);'
          + (props.edit ? 'box-shadow:0 0 0 1px color-mix(in srgb,var(--app-accent) 40%,transparent) inset;' : ''),
      }, children)
    }
  },
})

/** Shared style for the small round edit-overlay buttons. */
function editBtnStyle(pos: string): string {
  return `position:absolute;${pos}z-index:5;width:22px;height:22px;border-radius:11px;border:none;cursor:pointer;`
    + 'display:flex;align-items:center;justify-content:center;font-size:11px;line-height:1;'
    + 'background:var(--app-accent);color:var(--app-accent-foreground,#fff);'
}

export async function mountWidgets(boot: WidgetsBoot): Promise<void> {
  if (mounted) return
  mounted = true
  const router = createRouter({ history: createMemoryHistory(), routes: [{ path: '/:p(.*)*', component: { render: () => null } }] })
  const Root = defineComponent({
    setup() {
      // 12-column dense grid matching the host HomePage: each widget spans
      // its WxH from the sizeKey; `dense` packing closes gaps.
      const cells: unknown[] = (boot.widgets ?? []).map((p, i) =>
        h(WidgetCell, { placement: p, edit: boot.edit, key: `${p.spaceId}.${p.widgetId}.${i}` }))
      // In edit mode, a trailing "+" tile to add a widget on the grid.
      if (boot.edit) {
        cells.push(h('button', {
          key: '__add__',
          onClick: () => postEdit({ type: 'add' }),
          style: 'grid-column: span 2; grid-row: span 1;border:1px dashed color-mix(in srgb,currentColor 25%,transparent);'
            + 'border-radius:0;background:transparent;color:var(--app-muted);cursor:pointer;font-size:22px;',
        }, '+'))
      }
      return h('div', {
        class: 'construct-space-root',
        style: 'height:100%;overflow:auto;padding:16px;background:var(--app-canvas-bg);'
          + 'display:grid;grid-template-columns:repeat(12,minmax(0,1fr));grid-auto-rows:96px;'
          + 'grid-auto-flow:row dense;gap:12px;align-content:start;',
      }, cells)
    },
  })
  const app = createApp(Root)
  app.use(createPinia())
  app.use(router)
  app.component('Icon', UIIcon as ReturnType<typeof defineComponent>)
  app.config.errorHandler = (err, _i, info) => console.error(`[space-shell] widget error (${info}):`, err)
  app.mount('#app')
}
