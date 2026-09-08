/**
 * Host implementation of `@construct-space/sdk` exposed on
 * window.__CONSTRUCT__['@construct-space/sdk'].
 *
 * Assembles: the npm SDK's static surface (schemas, validators, data
 * composables that read window.construct) + faithful standalone ports of the
 * host composables/stores (./sdk/*) + a safe fallback for the long tail not yet
 * ported, so an unported call degrades instead of crashing the mount.
 */
import * as Sdk from '@construct-space/sdk'
import { defineComponent, h } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import * as ported from './sdk/composables'
import {
  useAuthStore, usePreferencesStore, useSettingsStore,
  useProjectStore, usePanelsStore,
} from './sdk/stores'
import { SplitPane, ToolbarSlot, ConfirmationModal } from './sdk/components'

// Concrete implementations (override the npm SDK's typed-but-unbound surface).
const concrete: Record<string, unknown> = {
  // stores
  useAuthStore, usePreferencesStore, useSettingsStore, useProjectStore, usePanelsStore,
  // composables (ported)
  useBreadcrumb: ported.useBreadcrumb,
  useToolbar: ported.useToolbar,
  useSidebar: ported.useSidebar,
  useNavigator: ported.useNavigator,
  useDateFormat: ported.useDateFormat,
  useMarkdown: ported.useMarkdown,
  renderMarkdown: ported.renderMarkdown,
  renderStreamingMarkdown: ported.renderStreamingMarkdown,
  useNotification: ported.useNotification,
  useToast: ported.useToast,
  // space context bus
  publishSpaceContext: ported.publishSpaceContext,
  subscribeSpaceContext: ported.subscribeSpaceContext,
  getLatestSpaceContext: ported.getLatestSpaceContext,
  registerContextHandler: ported.registerContextHandler,
  registerAutomationProvider: ported.registerAutomationProvider,
  getAutomationProvider: ported.getAutomationProvider,
  requestSpaceData: ported.requestSpaceData,
  useStorage: ported.useStorage,
  useScheduler: ported.useScheduler,
  useHttp: ported.useHttp,
  useDownload: ported.useDownload,
  useExport: ported.useExport,
  useImport: ported.useImport,
  useOrg: ported.useOrg,
  useOrgMembers: ported.useOrgMembers,
  useOrgTeams: ported.useOrgTeams,
  useOrgDepartments: ported.useOrgDepartments,
  useOrgRoles: ported.useOrgRoles,
  useAuthorization: ported.useAuthorization,
  useAccess: ported.useAccess,
  useConstructConfig: ported.useConstructConfig,
  getConstructRuntime: ported.getConstructRuntime,
  useTheme: ported.useAppTheme,
  useAppTheme: ported.useAppTheme,
  usePresenceStatus: ported.usePresenceStatus,
  useMediaSession: ported.useMediaSession,
  useSpaceShortcuts: ported.useSpaceShortcuts,
  // vue-router passthroughs the SDK surfaces
  useRoute, useRouter,
  // SDK-exported components
  SplitPane, ToolbarSlot, ConfirmationModal,
}

// Safe stub for host composables not yet ported (brain/tauri-bound, etc.).
function safeStub(name: string): () => unknown {
  return () => {
    console.warn(`[space-shell] @construct-space/sdk.${name}() is a stub (not yet ported).`)
    return new Proxy({}, {
      get(_t, key) {
        if (key === 'then') return undefined
        if (typeof key === 'symbol') return undefined
        return new Proxy(function () { return undefined } as object, { get() { return undefined }, apply() { return undefined } })
      },
    })
  }
}

const passthroughCache = new Map<string, unknown>()
function passthroughComponent(name: string): unknown {
  if (!passthroughCache.has(name)) {
    console.warn(`[space-shell] @construct-space/sdk component "${name}" is a passthrough stub.`)
    passthroughCache.set(name, defineComponent({
      name: `Stub_${name}`,
      setup: (_props, { slots }) => () => h('div', { class: `construct-stub-${name}` }, slots.default ? slots.default() : []),
    }))
  }
  return passthroughCache.get(name)
}

const base: Record<string, unknown> = { ...(Sdk as Record<string, unknown>), ...concrete }

export const sdkRuntime: Record<string, unknown> = new Proxy(base, {
  get(target, key) {
    if (typeof key === 'symbol') return Reflect.get(target, key)
    if (key in target) return target[key as string]
    const name = String(key)
    if (name.startsWith('use') || name.startsWith('get')) return safeStub(name)
    // Unknown PascalCase export → treat as a component and degrade to a
    // passthrough (renders its slot) so `<component :is>` never resolves to
    // undefined and crashes Vue with the `emitsOptions` null error.
    if (/^[A-Z]/.test(name)) return passthroughComponent(name)
    return undefined
  },
  has(target, key) { return key in target || String(key).startsWith('use') },
})
