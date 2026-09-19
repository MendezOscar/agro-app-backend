/** Formato de moneda de la app: lempiras hondureños. */
export const money = (n: number | null | undefined, decimals = 0) =>
  'L ' + (n ?? 0).toLocaleString('es-HN', { minimumFractionDigits: decimals, maximumFractionDigits: decimals })

/** Número con separador de miles, sin moneda. */
export const num = (n: number | null | undefined, decimals = 0) =>
  (n ?? 0).toLocaleString('es-HN', { minimumFractionDigits: decimals, maximumFractionDigits: decimals })

/** Fecha corta (12 sep 26). Acepta ISO o null. */
export const shortDate = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleDateString('es-HN', { day: '2-digit', month: 'short', year: '2-digit' }) : '—'

/** Fecha sin año (12 sep), para listas densas. */
export const dayMonth = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleDateString('es-HN', { day: '2-digit', month: 'short' }) : '—'
