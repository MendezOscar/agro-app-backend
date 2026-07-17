<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'
import { dashboardApi, cyclesApi, type Dashboard, type DashboardFarm } from '../api/resources'
import { computeAgronomy } from '../composables/agronomy'

const data = ref<Dashboard | null>(null)
const selectedFarm = ref<DashboardFarm | null>(null)
const weather = ref<Record<string, unknown> | null>(null)
const weatherLoading = ref(false)

// Códigos WMO → etiqueta + emoji (Open-Meteo weather_code)
const wmo: Record<number, [string, string]> = {
  0: ['Despejado', '☀️'], 1: ['Mayormente despejado', '🌤'], 2: ['Parcialmente nublado', '⛅'], 3: ['Nublado', '☁️'],
  45: ['Niebla', '🌫'], 48: ['Niebla', '🌫'], 51: ['Llovizna', '🌦'], 53: ['Llovizna', '🌦'], 55: ['Llovizna', '🌧'],
  61: ['Lluvia', '🌧'], 63: ['Lluvia', '🌧'], 65: ['Lluvia fuerte', '🌧'], 71: ['Nieve', '🌨'], 80: ['Chubascos', '🌦'],
  81: ['Chubascos', '🌧'], 82: ['Chubascos fuertes', '⛈'], 95: ['Tormenta', '⛈'], 96: ['Tormenta', '⛈'], 99: ['Tormenta', '⛈'],
}
const desc = (code: number) => wmo[code] ?? ['—', '🌡']

const stageLabels = ['Planificación', 'Prep. suelo', 'Siembra', 'Manejo', 'Monitoreo', 'Cosecha', 'Poscosecha', 'Evaluación']
const stageColor = (status: number) => ['#c8ccc4', '#d99a00', 'var(--leaf)'][status] ?? '#c8ccc4'
const costKindLabels = ['Mano de obra', 'Insumo', 'Maquinaria', 'Otro']
const money = (n: number) => n.toLocaleString('es', { maximumFractionDigits: 0 })
const alertColor = (lvl: string) => lvl === 'danger' ? '#dc2626' : (lvl === 'warning' ? '#d99a00' : 'var(--drop)')
const fmtDue = (iso: string | null) => iso ? new Date(iso).toLocaleDateString('es', { day: '2-digit', month: 'short' }) : '—'

// Alertas agronómicas (Open-Meteo desde el navegador, por ciclo activo).
const agroAlerts = ref<{ level: string; message: string }[]>([])
async function loadAgroAlerts() {
  if (!data.value) return
  const out: { level: string; message: string }[] = []
  for (const c of data.value.activeCyclesList) {
    try {
      const a = await computeAgronomy(await cyclesApi.agronomyContext(c.id))
      if (a.water?.irrigationSuggested)
        out.push({ level: 'warning', message: `Riego recomendado en ${c.crop}: ~${a.water.suggestedMm.toFixed(0)} mm (déficit 7 días).` })
      if (a.disease && (a.disease.level === 'high' || a.disease.level === 'medium'))
        out.push({ level: a.disease.level === 'high' ? 'danger' : 'warning', message: `Riesgo de enfermedad ${a.disease.level === 'high' ? 'alto' : 'medio'} en ${c.crop} (humedad/temperatura favorables a hongos).` })
    } catch { /* omitir si falla */ }
  }
  agroAlerts.value = out
}

onMounted(async () => {
  data.value = await dashboardApi.get()
  const withLoc = data.value.farmsList.find((f) => f.lat != null && f.lng != null)
  if (withLoc) selectedFarm.value = withLoc
  loadAgroAlerts()
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

const kpis = () => data.value ? [
  { label: 'Fincas', value: data.value.farms, icon: '🌱' },
  { label: 'Lotes', value: data.value.plots, icon: '🗺' },
  { label: 'Ciclos activos', value: data.value.activeCycles, icon: '🌾' },
  { label: 'Tareas pendientes', value: data.value.pendingTasks, icon: '✅' },
  { label: 'Ciclos cerrados', value: data.value.closedCycles, icon: '📦' },
  { label: 'Costo total', value: data.value.totalCost.toFixed(2), icon: '💲' },
] : []
</script>

<template>
  <h2>Inicio</h2>
  <div v-if="data">
    <!-- Alertas -->
    <div v-if="data.alerts.length || agroAlerts.length" style="margin-bottom:16px;display:flex;flex-direction:column;gap:8px">
      <div v-for="(a, i) in data.alerts" :key="'a' + i" class="card"
        :style="{ padding:'12px 16px', borderLeft:`4px solid ${alertColor(a.level)}`, display:'flex', alignItems:'center', gap:'10px' }">
        <span style="font-size:18px">{{ a.level === 'danger' ? '⚠️' : (a.level === 'warning' ? '🪲' : 'ℹ️') }}</span>
        <span style="font-weight:600">{{ a.message }}</span>
      </div>
      <div v-for="(a, i) in agroAlerts" :key="'g' + i" class="card"
        :style="{ padding:'12px 16px', borderLeft:`4px solid ${alertColor(a.level)}`, display:'flex', alignItems:'center', gap:'10px' }">
        <span style="font-size:18px">{{ a.message.startsWith('Riego') ? '💧' : '🍄' }}</span>
        <span style="font-weight:600">{{ a.message }}</span>
      </div>
    </div>

    <!-- KPIs -->
    <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:16px">
      <div v-for="k in kpis()" :key="k.label" class="card" style="padding:18px">
        <div style="font-size:26px">{{ k.icon }}</div>
        <div style="font-size:30px;font-weight:800;letter-spacing:-.02em;margin-top:6px">{{ k.value }}</div>
        <div class="muted">{{ k.label }}</div>
      </div>
    </div>

    <!-- Timeline de cultivos activos -->
    <div v-if="data.activeCyclesList.length" class="card" style="margin-top:20px">
      <h3 style="margin:0 0 4px">Avance de cultivos activos</h3>
      <router-link v-for="c in data.activeCyclesList" :key="c.id" :to="{ name: 'cycle', params: { id: c.id } }"
        class="cycle-row" style="display:block;text-decoration:none;color:var(--ink);margin-top:12px;padding:10px;border-radius:12px">
        <div style="display:flex;align-items:center;gap:8px">
          <span style="font-weight:700">{{ c.crop }}<span v-if="c.variety" class="muted"> · {{ c.variety }}</span></span>
          <span style="flex:1"></span>
          <span style="font-weight:700;color:var(--leaf)">${{ money(c.totalCost) }}</span>
          <span class="muted" style="font-size:13px">Ver ciclo →</span>
        </div>
        <div style="display:flex;align-items:flex-start;margin-top:10px;overflow-x:auto;padding-bottom:6px">
          <template v-for="(s, i) in c.stages" :key="s.kind">
            <div style="flex:1;min-width:64px;display:flex;flex-direction:column;align-items:center;position:relative">
              <div style="display:flex;align-items:center;width:100%">
                <div :style="{ flex: 1, height: '3px', background: i === 0 ? 'transparent' : stageColor(c.stages[i-1].status) }"></div>
                <div :style="{ width: '26px', height: '26px', borderRadius: '50%', background: stageColor(s.status),
                  color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '12px', fontWeight: 700, flexShrink: 0 }">
                  <span v-if="s.status === 2">✓</span><span v-else>{{ s.kind + 1 }}</span>
                </div>
                <div :style="{ flex: 1, height: '3px', background: i === c.stages.length - 1 ? 'transparent' : stageColor(s.status) }"></div>
              </div>
              <div class="muted" style="font-size:11px;text-align:center;margin-top:6px;line-height:1.2">{{ stageLabels[s.kind] }}</div>
            </div>
          </template>
        </div>
      </router-link>
    </div>

    <div class="row" style="margin-top:20px;gap:16px">
      <!-- Tareas por vencer -->
      <div class="card" style="flex:1;min-width:300px">
        <h3 style="margin:0 0 10px">Tareas por vencer</h3>
        <div v-if="!data.upcomingTasks.length" class="muted">Sin tareas pendientes con fecha.</div>
        <div v-for="t in data.upcomingTasks" :key="t.id"
          style="display:flex;align-items:center;gap:10px;padding:8px 0;border-bottom:1px solid var(--border)">
          <span :style="{ width:'8px', height:'8px', borderRadius:'50%', background: t.overdue ? '#dc2626' : 'var(--leaf)', flexShrink:0 }"></span>
          <div style="flex:1">
            <div style="font-weight:600">{{ t.title }}</div>
            <div class="muted" style="font-size:12px">{{ t.crop }}</div>
          </div>
          <span :style="{ fontSize:'13px', fontWeight:600, color: t.overdue ? '#dc2626' : '#555' }">
            {{ t.overdue ? 'Vencida · ' : '' }}{{ fmtDue(t.dueDate) }}
          </span>
        </div>
      </div>

      <!-- Costo por tipo -->
      <div class="card" style="flex:1;min-width:300px">
        <h3 style="margin:0 0 10px">Costo por tipo</h3>
        <div v-if="!data.costByKind.length" class="muted">Sin costos registrados.</div>
        <template v-else>
          <div v-for="s in data.costByKind" :key="s.kind" style="margin:8px 0">
            <div style="display:flex;justify-content:space-between;font-size:14px;margin-bottom:3px">
              <span>{{ costKindLabels[s.kind] }}</span>
              <strong>${{ money(s.total) }}</strong>
            </div>
            <div style="height:8px;background:#eef1ea;border-radius:6px;overflow:hidden">
              <div :style="{ width: (data.totalCost ? (s.total / data.totalCost * 100) : 0) + '%', height:'100%', background:'var(--leaf)' }"></div>
            </div>
          </div>
          <div style="display:flex;justify-content:space-between;margin-top:12px;padding-top:10px;border-top:2px solid var(--border);font-weight:800">
            <span>Total</span><span>${{ money(data.totalCost) }}</span>
          </div>
        </template>
      </div>
    </div>

    <!-- Clima -->
    <div class="card" style="margin-top:20px">
      <div style="display:flex;align-items:center;gap:12px;flex-wrap:wrap">
        <h3 style="margin:0;flex:1">Clima por finca</h3>
        <select v-if="data!.farmsList.length" :value="selectedFarm?.id"
          @change="selectedFarm = data!.farmsList.find(f => f.id === ($event.target as HTMLSelectElement).value) ?? null">
          <option v-for="f in data!.farmsList" :key="f.id" :value="f.id" :disabled="f.lat == null">
            {{ f.name }}{{ f.lat == null ? ' (sin ubicación)' : '' }}
          </option>
        </select>
      </div>

      <div v-if="weatherLoading" class="muted" style="margin-top:12px">Cargando clima…</div>
      <div v-else-if="!selectedFarm || selectedFarm.lat == null" class="muted" style="margin-top:12px">
        Selecciona una finca con ubicación en el mapa para ver el clima.
      </div>
      <div v-else-if="weather && (weather as any).current" style="margin-top:14px">
        <div style="display:flex;align-items:center;gap:20px;flex-wrap:wrap">
          <div style="font-size:52px">{{ desc((weather as any).current.weather_code)[1] }}</div>
          <div>
            <div style="font-size:40px;font-weight:800">{{ Math.round((weather as any).current.temperature_2m) }}°C</div>
            <div class="muted">{{ desc((weather as any).current.weather_code)[0] }}</div>
          </div>
          <div style="display:flex;gap:24px;flex-wrap:wrap">
            <div><div class="muted">Humedad</div><strong>{{ (weather as any).current.relative_humidity_2m }}%</strong></div>
            <div><div class="muted">Lluvia</div><strong>{{ (weather as any).current.precipitation }} mm</strong></div>
            <div><div class="muted">Viento</div><strong>{{ (weather as any).current.wind_speed_10m }} km/h</strong></div>
          </div>
        </div>
        <!-- Pronóstico 5 días -->
        <div style="display:grid;grid-template-columns:repeat(5,1fr);gap:10px;margin-top:18px">
          <div v-for="(d, i) in (weather as any).daily.time" :key="d"
            style="text-align:center;padding:12px 6px;background:#f7f9f5;border-radius:12px;border:1px solid var(--border)">
            <div class="muted" style="font-size:12px">{{ new Date(d).toLocaleDateString('es', { weekday: 'short' }) }}</div>
            <div style="font-size:24px;margin:4px 0">{{ desc((weather as any).daily.weather_code[i])[1] }}</div>
            <div style="font-weight:700;font-size:13px">{{ Math.round((weather as any).daily.temperature_2m_max[i]) }}°</div>
            <div class="muted" style="font-size:12px">{{ Math.round((weather as any).daily.temperature_2m_min[i]) }}°</div>
            <div style="font-size:11px;color:var(--drop)">💧 {{ (weather as any).daily.precipitation_sum[i] }}mm</div>
          </div>
        </div>
        <div class="muted" style="margin-top:8px;font-size:11px">Datos: Open-Meteo</div>
      </div>
    </div>
  </div>
  <div v-else class="muted">Cargando…</div>
</template>
