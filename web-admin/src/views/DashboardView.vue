<script setup lang="ts">
import { computed, onMounted, nextTick, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import maplibregl from 'maplibre-gl'
import Message from 'primevue/message'
import Select from 'primevue/select'
import Tag from 'primevue/tag'
import { dashboardApi, cyclesApi, type Dashboard, type DashboardFarm } from '../api/resources'
import { computeAgronomy } from '../composables/agronomy'
import { money, num, dayMonth } from '../utils/format'
import PageHeader from '../components/PageHeader.vue'
import SectionCard from '../components/SectionCard.vue'
import StatCard from '../components/StatCard.vue'
import StageProgress from '../components/StageProgress.vue'
import EmptyState from '../components/EmptyState.vue'

const router = useRouter()
const data = ref<Dashboard | null>(null)
const selectedFarm = ref<DashboardFarm | null>(null)
const weather = ref<Record<string, unknown> | null>(null)
const weatherLoading = ref(false)

// Mapa rápido de incidentes geolocalizados (todas las observaciones con GPS).
const mapEl = ref<HTMLElement | null>(null)
const mapToken = import.meta.env.VITE_MAPTILER_KEY as string
const sevColors: Record<string, string> = { high: '#dc2626', medium: '#ea580c', low: '#ca8a04', none: '#16a34a' }
const sevLabels: Record<string, string> = { high: 'Alta', medium: 'Media', low: 'Baja', none: 'Sin incidencia' }
let incMap: maplibregl.Map | null = null
// Semáforo por lote (peor estado de sus ciclos) y viento de la finca principal.
const plotRisk = ref<Record<string, { color: string; label: string }>>({})
const dashWind = ref<{ speed: number; dir: number; gust: number } | null>(null)

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function riskFromAgro(a: any): { color: string; label: string } {
  const danger = a?.disease?.level === 'high' || a?.alerts?.some((x: { level: string }) => x.level === 'danger')
  const warn = a?.disease?.level === 'medium' || a?.water?.irrigationSuggested || a?.alerts?.some((x: { level: string }) => x.level === 'warning')
  if (danger) return { color: '#dc2626', label: 'Riesgo alto' }
  if (warn) return { color: '#ea580c', label: 'Precaución' }
  return { color: '#16a34a', label: 'Sin alertas' }
}
function dashDrift(): { color: string; label: string } | null {
  if (!dashWind.value) return null
  const s = Math.max(dashWind.value.speed, dashWind.value.gust)
  if (s > 25) return { color: '#dc2626', label: 'No aplicar' }
  if (s > 15) return { color: '#ea580c', label: 'Precaución' }
  return { color: '#16a34a', label: 'Apta' }
}
function recolorPlots() {
  const m = incMap
  if (!m) return
  for (const [plotId, r] of Object.entries(plotRisk.value)) {
    if (!m.getLayer(`plot-${plotId}-fill`)) continue
    m.setPaintProperty(`plot-${plotId}-fill`, 'fill-color', r.color)
    m.setPaintProperty(`plot-${plotId}-line`, 'line-color', r.color)
  }
}

function initIncidentsMap() {
  if (!mapToken || !mapEl.value || incMap || !data.value?.incidents.length) return
  const first = data.value.incidents[0]
  const m = new maplibregl.Map({
    container: mapEl.value,
    style: `https://api.maptiler.com/maps/hybrid/style.json?key=${mapToken}`,
    center: [first.lng, first.lat],
    zoom: 12,
  })
  m.addControl(new maplibregl.NavigationControl({ showCompass: true }), 'top-right')
  m.on('load', () => {
    const bounds = new maplibregl.LngLatBounds()
    for (const p of data.value!.plotBoundaries) {
      if (!p.boundary) continue
      const src = `plot-${p.id}`
      m.addSource(src, { type: 'geojson', data: { type: 'Feature', properties: {}, geometry: { type: 'Polygon', coordinates: [p.boundary] } } })
      m.addLayer({ id: `${src}-fill`, type: 'fill', source: src, paint: { 'fill-color': '#22c55e', 'fill-opacity': 0.15 } })
      m.addLayer({ id: `${src}-line`, type: 'line', source: src, paint: { 'line-color': '#22c55e', 'line-width': 2 } })
      for (const c of p.boundary) bounds.extend(c as [number, number])
    }
    for (const o of data.value!.incidents) {
      const color = o.severity ? sevColors[o.severity] ?? '#64748b' : '#64748b'
      const el = document.createElement('div')
      el.style.cssText = `width:15px;height:15px;border-radius:50%;border:2px solid #fff;box-shadow:0 0 0 1px rgba(0,0,0,.3);cursor:pointer;background:${color}`
      const html =
        `<div style="font-weight:600">${o.crop}</div>` +
        (o.note ? `<div style="margin-top:2px">${o.note.replace(/[<>&]/g, '')}</div>` : '') +
        (o.severity ? `<div style="margin-top:4px;color:${color}">Severidad: ${sevLabels[o.severity] || o.severity}</div>` : '<div style="margin-top:4px;color:#64748b">Análisis IA en proceso…</div>') +
        `<div style="margin-top:6px"><a href="#" data-cycle="${o.cycleId}" class="inc-link">Ver ciclo →</a></div>`
      const popup = new maplibregl.Popup({ offset: 14 }).setHTML(`<div style="max-width:200px">${html}</div>`)
      popup.on('open', () => {
        const a = popup.getElement()?.querySelector('.inc-link') as HTMLElement | null
        a?.addEventListener('click', (e) => { e.preventDefault(); router.push({ name: 'cycle', params: { id: o.cycleId } }) })
      })
      new maplibregl.Marker({ element: el }).setLngLat([o.lng, o.lat]).setPopup(popup).addTo(m)
      bounds.extend([o.lng, o.lat])
    }
    if (!bounds.isEmpty()) m.fitBounds(bounds, { padding: 50, maxZoom: 15 })
    recolorPlots() // aplica el semáforo si la agronomía ya está lista
  })
  incMap = m
}

// Códigos WMO → etiqueta + icono (Open-Meteo weather_code)
const wmo: Record<number, [string, string]> = {
  0: ['Despejado', '☀️'], 1: ['Mayormente despejado', '🌤'], 2: ['Parcialmente nublado', '⛅'], 3: ['Nublado', '☁️'],
  45: ['Niebla', '🌫'], 48: ['Niebla', '🌫'], 51: ['Llovizna', '🌦'], 53: ['Llovizna', '🌦'], 55: ['Llovizna', '🌧'],
  61: ['Lluvia', '🌧'], 63: ['Lluvia', '🌧'], 65: ['Lluvia fuerte', '🌧'], 71: ['Nieve', '🌨'], 80: ['Chubascos', '🌦'],
  81: ['Chubascos', '🌧'], 82: ['Chubascos fuertes', '⛈'], 95: ['Tormenta', '⛈'], 96: ['Tormenta', '⛈'], 99: ['Tormenta', '⛈'],
}
const desc = (code: number) => wmo[code] ?? ['—', '🌡']

const costKindLabels = ['Mano de obra', 'Insumo', 'Maquinaria', 'Otro']
const alertSeverity = (lvl: string) => (lvl === 'danger' ? 'error' : lvl === 'warning' ? 'warn' : 'info')

// Alertas agronómicas (Open-Meteo desde el navegador, por ciclo activo).
const agroAlerts = ref<{ level: string; message: string }[]>([])
const allAlerts = computed(() => [...(data.value?.alerts ?? []), ...agroAlerts.value])
const showAllAlerts = ref(false)
const visibleAlerts = computed(() => (showAllAlerts.value ? allAlerts.value : allAlerts.value.slice(0, 3)))

async function loadAgroAlerts() {
  if (!data.value) return
  const out: { level: string; message: string }[] = []
  const rank: Record<string, number> = { '#16a34a': 0, '#ea580c': 1, '#dc2626': 2 }
  const byPlot: Record<string, { color: string; label: string }> = {}
  for (const c of data.value.activeCyclesList) {
    try {
      const a = await computeAgronomy(await cyclesApi.agronomyContext(c.id))
      const r = riskFromAgro(a)
      const prev = byPlot[c.plotId]
      if (!prev || rank[r.color] > rank[prev.color]) byPlot[c.plotId] = r
      if (a.water?.irrigationSuggested)
        out.push({ level: 'warning', message: `Riego recomendado en ${c.crop}: ~${a.water.suggestedMm.toFixed(0)} mm (déficit de 7 días).` })
      if (a.disease && (a.disease.level === 'high' || a.disease.level === 'medium'))
        out.push({ level: a.disease.level === 'high' ? 'danger' : 'warning', message: `Riesgo de enfermedad ${a.disease.level === 'high' ? 'alto' : 'medio'} en ${c.crop} (humedad y temperatura favorables a hongos).` })
      for (const w of a.alerts) out.push({ level: w.level, message: `${w.message} (${c.crop})` })
    } catch { /* omitir si falla */ }
  }
  agroAlerts.value = out
  plotRisk.value = byPlot
  recolorPlots()
}

async function loadDashWind() {
  const f = data.value?.farmsList.find((x) => x.lat != null && x.lng != null)
  if (!f) return
  try {
    const url = `https://api.open-meteo.com/v1/forecast?latitude=${f.lat}&longitude=${f.lng}`
      + `&current=wind_speed_10m,wind_direction_10m,wind_gusts_10m&timezone=auto`
    const c = (await (await fetch(url)).json()).current
    dashWind.value = { speed: c.wind_speed_10m ?? 0, dir: c.wind_direction_10m ?? 0, gust: c.wind_gusts_10m ?? 0 }
  } catch { dashWind.value = null }
}

onMounted(async () => {
  data.value = await dashboardApi.get()
  const withLoc = data.value.farmsList.find((f) => f.lat != null && f.lng != null)
  if (withLoc) selectedFarm.value = withLoc
  await nextTick()
  initIncidentsMap()
  loadAgroAlerts()
  loadDashWind()
})

watch(selectedFarm, loadWeather)

async function loadWeather() {
  const f = selectedFarm.value
  if (!f || f.lat == null || f.lng == null) { weather.value = null; return }
  weatherLoading.value = true
  try {
    const url = `https://api.open-meteo.com/v1/forecast?latitude=${f.lat}&longitude=${f.lng}`
      + `&current=temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m,weather_code`
      + `&daily=temperature_2m_max,temperature_2m_min,precipitation_sum,weather_code&timezone=auto&forecast_days=5`
    const res = await fetch(url)
    weather.value = await res.json()
  } catch {
    weather.value = null
  } finally {
    weatherLoading.value = false
  }
}

const kpis = computed(() => {
  const d = data.value
  if (!d) return []
  return [
    { label: 'Fincas', value: num(d.farms), icon: 'pi-map-marker' },
    { label: 'Lotes', value: num(d.plots), icon: 'pi-th-large' },
    { label: 'Ciclos activos', value: num(d.activeCycles), icon: 'pi-sun', tone: 'ok' as const },
    {
      label: 'Tareas pendientes', value: num(d.pendingTasks), icon: 'pi-check-square',
      tone: d.overdueTasks ? ('danger' as const) : undefined,
      hint: d.overdueTasks ? `${d.overdueTasks} vencida(s)` : undefined,
    },
    { label: 'Ciclos cerrados', value: num(d.closedCycles), icon: 'pi-inbox' },
    { label: 'Costo acumulado', value: money(d.totalCost), icon: 'pi-wallet' },
  ]
})
</script>

<template>
  <div v-if="data" class="stack">
    <PageHeader title="Inicio" subtitle="Resumen de la operación: alertas, avance de los cultivos y costos." />

    <!-- Alertas -->
    <div v-if="allAlerts.length" class="alerts">
      <Message
        v-for="(a, i) in visibleAlerts" :key="i" :severity="alertSeverity(a.level)" :closable="false"
      >{{ a.message }}</Message>
      <button v-if="allAlerts.length > 3" class="more" @click="showAllAlerts = !showAllAlerts">
        {{ showAllAlerts ? 'Ver menos' : `Ver ${allAlerts.length - 3} alerta(s) más` }}
      </button>
    </div>

    <!-- Indicadores -->
    <div class="grid-kpi">
      <StatCard v-for="k in kpis" :key="k.label" v-bind="k" />
    </div>

    <div class="split">
      <div class="stack">
        <!-- Avance de cultivos activos -->
        <SectionCard
          title="Avance de cultivos activos" icon="pi-chart-line"
          :subtitle="`${data.activeCyclesList.length} ciclo(s) en curso`"
        >
          <EmptyState v-if="!data.activeCyclesList.length" icon="pi-sun" text="No hay ciclos activos." hint="Crea uno desde Fincas y lotes." />
          <router-link
            v-for="c in data.activeCyclesList" :key="c.id"
            :to="{ name: 'cycle', params: { id: c.id } }" class="cycle-row"
          >
            <div class="cycle-top">
              <strong>{{ c.crop }}</strong>
              <span v-if="c.variety" class="muted">· {{ c.variety }}</span>
              <span style="flex:1" />
              <span class="num cost">{{ money(c.totalCost) }}</span>
              <i class="pi pi-angle-right" />
            </div>
            <StageProgress :stages="c.stages" />
          </router-link>
        </SectionCard>

        <!-- Mapa de incidentes -->
        <SectionCard
          v-if="mapToken && data.incidents.length" title="Incidentes en el mapa" icon="pi-map"
          :subtitle="`${data.incidents.length} observación(es) geolocalizada(s)`"
        >
          <div class="map-wrap">
            <div ref="mapEl" class="inc-map" />
            <div class="map-hud" v-if="dashWind">
              <div class="hud-row">
                <span class="hud-arrow" :style="{ transform: `rotate(${dashWind.dir + 180}deg)` }">↑</span>
                <span>Viento <strong>{{ Math.round(dashWind.speed) }} km/h</strong><span v-if="dashWind.gust > dashWind.speed + 3" class="muted"> · ráfagas {{ Math.round(dashWind.gust) }}</span></span>
              </div>
              <div class="hud-row" v-if="dashDrift()">
                <span class="hud-dot" :style="{ background: dashDrift()!.color }" />
                <span>Aspersión: <strong :style="{ color: dashDrift()!.color }">{{ dashDrift()!.label }}</strong></span>
              </div>
            </div>
          </div>
          <p class="tiny map-note">
            Los pines usan el color de la severidad detectada por IA y abren el ciclo al hacer clic. El contorno de
            cada lote refleja su estado agronómico y el recuadro muestra el viento y la aptitud para aspersión.
          </p>
        </SectionCard>
      </div>

      <div class="stack">
        <!-- Tareas por vencer -->
        <SectionCard title="Tareas por vencer" icon="pi-calendar">
          <EmptyState v-if="!data.upcomingTasks.length" icon="pi-check-circle" text="Sin tareas pendientes con fecha." />
          <ul v-else class="tasks">
            <li v-for="t in data.upcomingTasks" :key="t.id">
              <span class="bullet" :class="{ late: t.overdue }" />
              <div class="task-text">
                <strong>{{ t.title }}</strong>
                <span class="muted">{{ t.crop }}</span>
              </div>
              <Tag
                :value="(t.overdue ? 'Vencida · ' : '') + dayMonth(t.dueDate)"
                :severity="t.overdue ? 'danger' : 'secondary'"
              />
            </li>
          </ul>
        </SectionCard>

        <!-- Costo por tipo -->
        <SectionCard title="Costo por tipo" icon="pi-wallet" :subtitle="money(data.totalCost) + ' acumulados'">
          <EmptyState v-if="!data.costByKind.length" icon="pi-wallet" text="Sin costos registrados." />
          <template v-else>
            <div v-for="s in data.costByKind" :key="s.kind" class="bar-item">
              <div class="bar-head">
                <span>{{ costKindLabels[s.kind] }}</span>
                <strong class="num">{{ money(s.total) }}</strong>
              </div>
              <div class="bar"><span :style="{ width: (data.totalCost ? (s.total / data.totalCost * 100) : 0) + '%' }" /></div>
            </div>
          </template>
        </SectionCard>
      </div>
    </div>

    <!-- Clima -->
    <SectionCard title="Clima por finca" icon="pi-cloud" subtitle="Datos de Open-Meteo, actualizados al abrir el panel.">
      <template #actions>
        <Select
          v-if="data.farmsList.length" v-model="selectedFarm" :options="data.farmsList"
          option-label="name" :option-disabled="(f: DashboardFarm) => f.lat == null" size="small" class="farm-select"
        />
      </template>

      <div v-if="weatherLoading" class="muted">Cargando clima…</div>
      <EmptyState
        v-else-if="!selectedFarm || selectedFarm.lat == null" icon="pi-map-marker"
        text="Esta finca no tiene ubicación." hint="Dibújala en el mapa desde Fincas y lotes para ver su clima."
      />
      <div v-else-if="weather && (weather as any).current">
        <div class="now">
          <div class="now-icon">{{ desc((weather as any).current.weather_code)[1] }}</div>
          <div>
            <div class="now-temp num">{{ Math.round((weather as any).current.temperature_2m) }}°C</div>
            <div class="muted">{{ desc((weather as any).current.weather_code)[0] }}</div>
          </div>
          <div class="now-stats">
            <div><span class="muted">Humedad</span><strong class="num">{{ (weather as any).current.relative_humidity_2m }}%</strong></div>
            <div><span class="muted">Lluvia</span><strong class="num">{{ (weather as any).current.precipitation }} mm</strong></div>
            <div><span class="muted">Viento</span><strong class="num">{{ (weather as any).current.wind_speed_10m }} km/h</strong></div>
          </div>
        </div>
        <div class="forecast">
          <div v-for="(d, i) in (weather as any).daily.time" :key="d" class="day">
            <div class="tiny">{{ new Date(d).toLocaleDateString('es', { weekday: 'short' }) }}</div>
            <div class="day-icon">{{ desc((weather as any).daily.weather_code[i])[1] }}</div>
            <div class="day-max num">{{ Math.round((weather as any).daily.temperature_2m_max[i]) }}°</div>
            <div class="tiny num">{{ Math.round((weather as any).daily.temperature_2m_min[i]) }}°</div>
            <div class="day-rain num">{{ (weather as any).daily.precipitation_sum[i] }} mm</div>
          </div>
        </div>
      </div>
    </SectionCard>
  </div>

  <div v-else class="muted">Cargando…</div>
</template>

<style scoped>
.alerts { display: flex; flex-direction: column; gap: 8px; }
.alerts .more {
  align-self: flex-start; background: none; border: none; cursor: pointer; font: inherit;
  font-size: 13px; font-weight: 600; color: var(--leaf-dark); padding: 2px 0;
}

.cycle-row {
  display: block; text-decoration: none; color: var(--ink); padding: 12px;
  border-radius: 12px; border: 1px solid transparent; transition: background .15s, border-color .15s;
}
.cycle-row + .cycle-row { margin-top: 4px; }
.cycle-row:hover { background: #f7f9f5; border-color: var(--border); }
.cycle-top { display: flex; align-items: center; gap: 6px; margin-bottom: 8px; }
.cycle-top .cost { font-weight: 700; color: var(--leaf-dark); }
.cycle-top i { color: var(--muted); font-size: 12px; }

.inc-map { height: 330px; border-radius: 12px; overflow: hidden; }
.map-note { margin: 8px 0 0; line-height: 1.5; }

.tasks { list-style: none; margin: 0; padding: 0; }
.tasks li { display: flex; align-items: center; gap: 10px; padding: 9px 0; border-bottom: 1px solid var(--border); }
.tasks li:last-child { border-bottom: none; }
.bullet { width: 8px; height: 8px; border-radius: 50%; background: var(--leaf); flex-shrink: 0; }
.bullet.late { background: var(--danger); }
.task-text { flex: 1; min-width: 0; display: flex; flex-direction: column; }
.task-text strong { font-size: 14px; }
.task-text span { font-size: 12px; }

.bar-item + .bar-item { margin-top: 12px; }
.bar-head { display: flex; justify-content: space-between; font-size: 13.5px; margin-bottom: 5px; }
.bar { height: 8px; background: #eef1ea; border-radius: 6px; overflow: hidden; }
.bar span { display: block; height: 100%; background: var(--leaf); border-radius: 6px; }

.farm-select { min-width: 200px; }
.now { display: flex; align-items: center; gap: 22px; flex-wrap: wrap; }
.now-icon { font-size: 46px; line-height: 1; }
.now-temp { font-size: 36px; font-weight: 800; letter-spacing: -.03em; }
.now-stats { display: flex; gap: 26px; flex-wrap: wrap; }
.now-stats div { display: flex; flex-direction: column; gap: 2px; }
.forecast { display: grid; grid-template-columns: repeat(5, 1fr); gap: 10px; margin-top: 18px; }
.day { text-align: center; padding: 12px 6px; background: #f7f9f5; border: 1px solid var(--border); border-radius: 12px; }
.day-icon { font-size: 22px; margin: 4px 0; }
.day-max { font-weight: 700; font-size: 13.5px; }
.day-rain { font-size: 11px; color: var(--drop); margin-top: 2px; }
</style>
