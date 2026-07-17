import type { AgronomyContext, AgronomyResult, SoilLayer } from '../api/resources'

// Calcula indicadores agronómicos llamando a Open-Meteo desde el navegador (IP propia,
// evita el límite por IP compartida de Render). Espeja la lógica que estaba en el backend.

function sum(arr: (number | null)[]): number {
  return arr.reduce<number>((a, v) => a + (v ?? 0), 0)
}
function lastValidIndex(arr: (number | null)[]): number {
  for (let i = arr.length - 1; i >= 0; i--) if (arr[i] != null) return i
  return -1
}

export async function computeAgronomy(ctx: AgronomyContext): Promise<AgronomyResult> {
  if (ctx.message || ctx.lat == null || ctx.lng == null) {
    return { soil: [], water: null, gdd: null, disease: null, source: '', message: ctx.message ?? 'Sin ubicación.' }
  }
  const soil: SoilLayer[] = []
  let water: AgronomyResult['water'] = null
  let gdd: AgronomyResult['gdd'] = null
  let disease: AgronomyResult['disease'] = null

  // --- Pronóstico: suelo actual, balance hídrico (7+7) y riesgo de enfermedad ---
  try {
    const fc = await fetch(`https://api.open-meteo.com/v1/forecast?latitude=${ctx.lat}&longitude=${ctx.lng}` +
      '&hourly=soil_temperature_0cm,soil_temperature_6cm,soil_temperature_18cm,soil_temperature_54cm,' +
      'soil_moisture_0_1cm,soil_moisture_1_3cm,soil_moisture_3_9cm,soil_moisture_9_27cm,' +
      'relative_humidity_2m,temperature_2m' +
      '&daily=et0_fao_evapotranspiration,precipitation_sum&past_days=7&forecast_days=7&timezone=auto')
      .then((r) => r.json())
    const h = fc.hourly
    if (h) {
      const idx = lastValidIndex(h.temperature_2m ?? [])
      const at = (k: string): number | null => (idx >= 0 && h[k] ? h[k][idx] ?? null : null)
      const pct = (v: number | null): number | null => (v == null ? null : Math.round(v * 1000) / 10)
      soil.push({ depthLabel: '0 cm', tempC: at('soil_temperature_0cm'), moisturePct: pct(at('soil_moisture_0_1cm')) })
      soil.push({ depthLabel: '6 cm', tempC: at('soil_temperature_6cm'), moisturePct: pct(at('soil_moisture_1_3cm')) })
      soil.push({ depthLabel: '18 cm', tempC: at('soil_temperature_18cm'), moisturePct: pct(at('soil_moisture_3_9cm')) })
      soil.push({ depthLabel: '54 cm', tempC: at('soil_temperature_54cm'), moisturePct: pct(at('soil_moisture_9_27cm')) })

      const rh: (number | null)[] = h.relative_humidity_2m ?? []
      const temp: (number | null)[] = h.temperature_2m ?? []
      const n = Math.min(rh.length, temp.length)
      const from = Math.max(0, n - 48)
      let favorable = 0
      for (let i = from; i < n; i++)
        if (rh[i] != null && temp[i] != null && rh[i]! >= 85 && temp[i]! >= 15 && temp[i]! <= 28) favorable++
      const level = favorable >= 18 ? 'high' : favorable >= 8 ? 'medium' : favorable >= 3 ? 'low' : 'none'
      disease = { level, reason: `${favorable} h con humedad ≥85% y 15–28 °C en las últimas 48 h (favorable a hongos).` }
    }
    const d = fc.daily
    if (d) {
      const et0 = sum(d.et0_fao_evapotranspiration ?? [])
      const pr = sum(d.precipitation_sum ?? [])
      const deficit = Math.max(0, et0 - pr)
      water = {
        et0Mm7d: Math.round(et0 * 10) / 10, precipMm7d: Math.round(pr * 10) / 10,
        deficitMm: Math.round(deficit * 10) / 10, irrigationSuggested: deficit > 15, suggestedMm: Math.round(deficit),
      }
    }
  } catch { /* pronóstico opcional */ }

  // --- Histórico: grados-día acumulados desde el inicio del ciclo ---
  const today = new Date()
  if (ctx.cycleStart && new Date(ctx.cycleStart) < today) {
    try {
      const end = new Date(today.getTime() - 86400000).toISOString().slice(0, 10)
      const arc = await fetch(`https://archive-api.open-meteo.com/v1/archive?latitude=${ctx.lat}&longitude=${ctx.lng}` +
        `&start_date=${ctx.cycleStart}&end_date=${end}` +
        '&daily=temperature_2m_max,temperature_2m_min&timezone=auto').then((r) => r.json())
      const dd = arc.daily
      if (dd) {
        const tmax: (number | null)[] = dd.temperature_2m_max ?? []
        const tmin: (number | null)[] = dd.temperature_2m_min ?? []
        const n = Math.min(tmax.length, tmin.length)
        let acc = 0, days = 0
        for (let i = 0; i < n; i++) {
          if (tmax[i] == null || tmin[i] == null) continue
          acc += Math.max(0, (tmax[i]! + tmin[i]!) / 2 - ctx.baseTempC)
          days++
        }
        gdd = { baseTempC: ctx.baseTempC, accumulated: Math.round(acc), days }
      }
    } catch { /* histórico opcional */ }
  }

  return { soil, water, gdd, disease, source: 'Open-Meteo', message: null }
}
