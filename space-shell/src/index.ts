/**
 * space-shell entry. Exposes a tiny global API the HTML shell calls in order:
 *   1. window.ConstructSpaceShell.initHost()      — populate window.__CONSTRUCT__
 *   2. <script src="app.iife.js">                 — registers __CONSTRUCT_SPACE_<ID>
 *   3. window.ConstructSpaceShell.mount(boot)     — render the pages
 *
 * window.construct (the runtime context) is injected natively by the Swift
 * SpaceHost bridge before this runs.
 */
import { initSpaceHost, HOST_API_VERSION } from './host'
import { mountSpace, mountWidgets, type SpaceBoot, type WidgetsBoot } from './mount'

const api = {
  HOST_API_VERSION,
  initHost: initSpaceHost,
  mount: (boot: SpaceBoot) => mountSpace(boot),
  mountWidgets: (boot: WidgetsBoot) => mountWidgets(boot),
}

;(window as unknown as Record<string, unknown>).ConstructSpaceShell = api

export default api
