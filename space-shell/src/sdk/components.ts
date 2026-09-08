/**
 * Minimal functional implementations of the Vue components the SDK re-exports
 * (ConfirmationModal, SplitPane, ToolbarSlot). Spaces import these from
 * `@construct-space/sdk`; without them the import is undefined and rendering
 * `<component :is="undefined">` throws Vue's `i.emitsOptions` error. These keep
 * layout/behavior close enough that spaces render; refine toward the host
 * components over time.
 */
import { defineComponent, h, ref, Teleport } from 'vue'

/** Two-pane master/detail layout. Supports `left`/`right` or default slots. */
export const SplitPane = defineComponent({
  name: 'SplitPane',
  props: {
    initialSize: { type: Number, default: 280 },
    minSize: { type: Number, default: 160 },
  },
  setup(props, { slots }) {
    const leftWidth = ref(props.initialSize)
    return () => h('div', { style: 'display:flex;height:100%;width:100%;overflow:hidden' }, [
      h('div', { style: `width:${leftWidth.value}px;min-width:${props.minSize}px;flex:0 0 auto;overflow:auto;border-right:1px solid var(--c-border,rgba(0,0,0,0.1))` },
        slots.left ? slots.left() : (slots.start ? slots.start() : [])),
      h('div', { style: 'flex:1 1 auto;overflow:auto' },
        slots.right ? slots.right() : (slots.end ? slots.end() : (slots.default ? slots.default() : []))),
    ])
  },
})

/** Teleports its content into the host toolbar region (#toolbar-left/center/
 *  right), matching the Tauri ToolbarSlot. The shell provides those targets. */
export const ToolbarSlot = defineComponent({
  name: 'ToolbarSlot',
  props: {
    name: { type: String, default: 'center' }, // left | center | right
    to: { type: String, default: '' },
  },
  setup(props, { slots }) {
    return () => {
      const target = props.to || `#toolbar-${props.name}`
      const exists = typeof document !== 'undefined' && !!document.querySelector(target)
      return h(Teleport, { to: target, disabled: !exists }, slots.default ? slots.default() : [])
    }
  },
})

/** Simple modal dialog. v-model:open; renders default slot when open. */
export const Modal = defineComponent({
  name: 'Modal',
  props: { open: { type: Boolean, default: false }, title: { type: String, default: '' } },
  emits: ['update:open', 'close'],
  setup(props, { emit, slots }) {
    const close = () => { emit('update:open', false); emit('close') }
    return () => !props.open ? null : h(Teleport, { to: 'body' }, [
      h('div', {
        style: 'position:fixed;inset:0;background:rgba(0,0,0,0.4);display:flex;align-items:center;justify-content:center;z-index:9999',
        onClick: close,
      }, [
        h('div', {
          style: 'background:var(--app-background,#fff);color:var(--app-foreground,#111);padding:20px;border-radius:12px;min-width:340px;max-width:90vw;max-height:85vh;overflow:auto;box-shadow:0 10px 40px rgba(0,0,0,0.3)',
          onClick: (e: Event) => e.stopPropagation(),
        }, [
          props.title ? h('h3', { style: 'margin:0 0 12px;font-size:16px' }, props.title) : null,
          slots.default ? slots.default() : [],
          slots.footer ? h('div', { style: 'margin-top:16px' }, slots.footer()) : null,
        ]),
      ]),
    ])
  },
})

/** Simple confirmation modal. Emits confirm/cancel; v-model:open supported. */
export const ConfirmationModal = defineComponent({
  name: 'ConfirmationModal',
  props: {
    open: { type: Boolean, default: false },
    title: { type: String, default: 'Confirm' },
    message: { type: String, default: '' },
    confirmLabel: { type: String, default: 'Confirm' },
    cancelLabel: { type: String, default: 'Cancel' },
  },
  emits: ['confirm', 'cancel', 'update:open'],
  setup(props, { emit, slots }) {
    const close = () => emit('update:open', false)
    return () => !props.open ? null : h(Teleport, { to: 'body' }, [
      h('div', {
        style: 'position:fixed;inset:0;background:rgba(0,0,0,0.4);display:flex;align-items:center;justify-content:center;z-index:9999',
        onClick: () => { emit('cancel'); close() },
      }, [
        h('div', {
          style: 'background:var(--c-bg,#fff);color:var(--c-fg,#111);padding:20px;border-radius:12px;min-width:320px;max-width:90vw;box-shadow:0 10px 40px rgba(0,0,0,0.3)',
          onClick: (e: Event) => e.stopPropagation(),
        }, [
          h('h3', { style: 'margin:0 0 8px;font-size:16px' }, props.title),
          slots.default ? slots.default() : h('p', { style: 'margin:0 0 16px;opacity:0.8' }, props.message),
          h('div', { style: 'display:flex;gap:8px;justify-content:flex-end;margin-top:16px' }, [
            h('button', { onClick: () => { emit('cancel'); close() } }, props.cancelLabel),
            h('button', {
              style: 'background:var(--c-accent,#6366f1);color:#fff;border:none;padding:6px 14px;border-radius:6px;cursor:pointer',
              onClick: () => { emit('confirm'); close() },
            }, props.confirmLabel),
          ]),
        ]),
      ]),
    ])
  },
})
