/**
 * Populates window.__CONSTRUCT__ with the host packages a space bundle
 * externalizes, matching construct-app's `initSpaceHost()` contract exactly
 * (same 11 keys, same Proxy guard, HOST_API_VERSION 0.6.0).
 *
 * The `@construct-space/sdk` entry is the HOST implementation of the SDK
 * surface, not the raw npm package — see ./sdkRuntime.
 */
import * as Vue from 'vue'
import * as VueRouter from 'vue-router'
import * as Pinia from 'pinia'
import * as VueUseCore from '@vueuse/core'
import * as VueUseIntegrations from '@vueuse/integrations'
import * as Lucide from 'lucide-vue-next'
import * as DateFns from 'date-fns'
import DexieDefault, * as DexieNs from 'dexie'
import * as Zod from 'zod'
import ConstructUIDefault, * as ConstructUI from '@construct-space/ui'
import { sdkRuntime } from './sdkRuntime'
import { Modal as ShellModal, ConfirmationModal as ShellConfirmationModal } from './sdk/components'

export const HOST_API_VERSION = '0.6.0'

declare global {
  interface Window {
    __CONSTRUCT__: Record<string, unknown>
  }
}

export function initSpaceHost(): void {
  if (window.__CONSTRUCT__) return

  const exposed: Record<string, unknown> = {
    'vue': Vue,
    'vue-router': VueRouter,
    'pinia': Pinia,
    '@vueuse/core': VueUseCore,
    '@vueuse/integrations': VueUseIntegrations,
    'lucide-vue-next': Lucide,
    'date-fns': DateFns,
    'dexie': Object.assign(DexieDefault, DexieNs),
    'zod': Zod,
    // Override Modal/ConfirmationModal with shell versions: the npm UI ones
    // crash under a per-space app instance (null-component vnode on update).
    '@construct-space/ui': Object.assign({}, ConstructUI, {
      default: ConstructUIDefault,
      Modal: ShellModal,
      ConfirmationModal: ShellConfirmationModal,
    }),
    '@construct-space/sdk': sdkRuntime,
  }

  // Same actionable Proxy guard as the host: a space that externalizes an
  // unexposed package fails loudly instead of getting `undefined`.
  window.__CONSTRUCT__ = new Proxy(exposed, {
    get(target, key) {
      if (typeof key === 'symbol') return Reflect.get(target, key)
      if (key in target) return (target as Record<string, unknown>)[key as string]
      throw new Error(
        `Space externalised "${String(key)}" but the space-shell runtime doesn't ` +
        `expose it. Add it to space-shell/src/host.ts.`,
      )
    },
    has(target, key) { return key in target },
    ownKeys(target) { return Reflect.ownKeys(target) },
    getOwnPropertyDescriptor(target, key) { return Reflect.getOwnPropertyDescriptor(target, key) },
  })
}
