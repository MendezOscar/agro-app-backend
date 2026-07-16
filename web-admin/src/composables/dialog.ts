import { ref } from 'vue'

export interface DialogState {
  title: string
  message: string
  okText: string
  danger: boolean
  hideCancel: boolean
  resolve: (v: boolean) => void
}

export const dialogState = ref<DialogState | null>(null)

/** Confirmación modal (reemplaza window.confirm). Resuelve true/false. */
export function confirmDialog(opts: string | Partial<Omit<DialogState, 'resolve'>>): Promise<boolean> {
  const o = typeof opts === 'string' ? { message: opts } : opts
  return new Promise((resolve) => {
    dialogState.value = {
      title: o.title ?? 'Confirmar',
      message: o.message ?? '',
      okText: o.okText ?? 'Aceptar',
      danger: o.danger ?? false,
      hideCancel: o.hideCancel ?? false,
      resolve,
    }
  })
}

/** Aviso modal (reemplaza window.alert). */
export function alertDialog(message: string, title = 'Aviso'): Promise<boolean> {
  return confirmDialog({ title, message, okText: 'Entendido', hideCancel: true })
}
