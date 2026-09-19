<script setup lang="ts">
import { computed, onMounted, nextTick, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import maplibregl from 'maplibre-gl'
import Button from 'primevue/button'
import Select from 'primevue/select'
import InputText from 'primevue/inputtext'
import InputNumber from 'primevue/inputnumber'
import Checkbox from 'primevue/checkbox'
import Tag from 'primevue/tag'
import Tabs from 'primevue/tabs'
import TabList from 'primevue/tablist'
import PrimeTab from 'primevue/tab'
import TabPanels from 'primevue/tabpanels'
import TabPanel from 'primevue/tabpanel'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Message from 'primevue/message'
import { useToast } from 'primevue/usetoast'
import {
  cyclesApi, farmsApi, inputsApi, tasksApi, usersApi,
  type Cycle, type Cost, type CycleReport, type Phenology, type Input, type WorkTask, type OrgUser, type Observation,
  type AgronomyResult, type PlotPhoto, type PlotProfitability, type FertilizationPlan, type Plot,
  type AmendmentDose, type RecommendedTask,
} from '../api/resources'
import { confirmDialog, alertDialog } from '../composables/dialog'
import { computeAgronomy } from '../composables/agronomy'
import { money, num, shortDate } from '../utils/format'
import PageHeader from '../components/PageHeader.vue'
import SectionCard from '../components/SectionCard.vue'
import StageProgress from '../components/StageProgress.vue'
import EmptyState from '../components/EmptyState.vue'

const stageLabels = ['Planificación', 'Prep. suelo', 'Siembra', 'Manejo', 'Monitoreo', 'Cosecha', 'Poscosecha', 'Evaluación']
const stageStatus = ['Pendiente', 'En progreso', 'Completada']
const cycleStatus = ['Planificada', 'Activa', 'Cosechada', 'Cerrada']
const costKind = ['Mano de obra', 'Insumo', 'Maquinaria', 'Otro']
const phenoStages = ['Germinación', 'Vegetativo', 'Floración', 'Cuajado', 'Maduración', 'Senescencia']
const taskStatusLabels = ['Por hacer', 'En progreso', 'Hecho']

const opts = (labels: string[]) => labels.map((label, value) => ({ label, value }))
const stageStatusOptions = opts(stageStatus)
const taskStatusOptions = opts(taskStatusLabels)
const costKindOptions = opts(costKind)
const phenoStageOptions = opts(phenoStages)

const route = useRoute()
const router = useRouter()
const toast = useToast()
const id = route.params.id as string

const cycle = ref<Cycle | null>(null)
const report = ref<CycleReport | null>(null)
const inputs = ref<Input[]>([])
const costs = ref<Cost[]>([])
const phenology = ref<Phenology[]>([])
const observations = ref<Observation[]>([])
const agronomy = ref<AgronomyResult | null>(null)
const plotPhotos = ref<PlotPhoto[]>([])
const profit = ref<PlotProfitability | null>(null)
const fert = ref<FertilizationPlan | null>(null)
const fertColors: Record<string, string> = { low: '#dc2626', ok: '#16a34a', high: '#ea580c' }
const fertLabels: Record<string, string> = { low: 'Bajo', ok: 'Adecuado', high: 'Alto' }
const diseaseLabels: Record<string, string> = { high: 'Alto', medium: 'Medio', low: 'Bajo', none: 'Sin riesgo' }
const cycleStatusSeverity = ['secondary', 'success', 'warn', 'contrast'] as const

// Mapa de incidentes: polígono del lote + un pin por observación geolocalizada.
const plot = ref<Plot | null>(null)
const mapEl = ref<HTMLElement | null>(null)
const mapToken = import.meta.env.VITE_MAPTILER_KEY as string
let incidentMap: maplibregl.Map | null = null
const wind = ref<{ speed: number; dir: number; gust: number } | null>(null)
// Caudal del sistema de riego (m³/h) para convertir el volumen a horas. Se recuerda localmente.
const caudal = ref<number>(Number(localStorage.getItem('agro_caudal')) || 20)
function setCaudal(v: number) { caudal.value = v > 0 ? v : 1; localStorage.setItem('agro_caudal', String(caudal.value)) }

// Semáforo del lote: peor estado agronómico actual (enfermedad / riego / clima extremo).
function plotRisk(): { color: string; label: string } {
  const a = agronomy.value
  if (!a) return { color: '#22c55e', label: 'Sin datos' }
  const danger = a.disease?.level === 'high' || a.alerts?.some((x) => x.level === 'danger')
  const warn = a.disease?.level === 'medium' || a.water?.irrigationSuggested || a.alerts?.some((x) => x.level === 'warning')
  if (danger) return { color: '#dc2626', label: 'Riesgo alto' }
  if (warn) return { color: '#ea580c', label: 'Precaución' }
  return { color: '#16a34a', label: 'Sin alertas' }
}

// Deriva de aspersión según viento (km/h). Regla de campo: aplicar bajo ~15 km/h.
function drift(): { color: string; label: string } | null {
  if (!wind.value) return null
  const s = Math.max(wind.value.speed, wind.value.gust)
  if (s > 25) return { color: '#dc2626', label: 'No aplicar' }
  if (s > 15) return { color: '#ea580c', label: 'Precaución' }
  return { color: '#16a34a', label: 'Apta' }
}

function applyPlotRisk() {
  const m = incidentMap
  if (!m || !m.getLayer('plot-fill')) return
  const { color } = plotRisk()
  m.setPaintProperty('plot-fill', 'fill-color', color)
  m.setPaintProperty('plot-line', 'line-color', color)
}
const geoObs = () => observations.value.filter((o) => o.location && o.location.length === 2)

function initIncidentMap() {
  if (!mapToken || !mapEl.value || incidentMap) return
  const pts = geoObs()
  if (!plot.value?.boundary && !pts.length) return
  const center = (plot.value?.boundary?.[0] as [number, number]) ?? (pts[0].location as [number, number])
  const m = new maplibregl.Map({
    container: mapEl.value,
    style: `https://api.maptiler.com/maps/hybrid/style.json?key=${mapToken}`,
    center,
    zoom: 15,
  })
  m.addControl(new maplibregl.NavigationControl({ showCompass: true }), 'top-right')
  m.on('load', () => {
    const ring = plot.value?.boundary
    const bounds = new maplibregl.LngLatBounds()
    if (ring) {
      m.addSource('plot', { type: 'geojson', data: { type: 'Feature', properties: {}, geometry: { type: 'Polygon', coordinates: [ring] } } })
      m.addLayer({ id: 'plot-fill', type: 'fill', source: 'plot', paint: { 'fill-color': '#22c55e', 'fill-opacity': 0.18 } })
      m.addLayer({ id: 'plot-line', type: 'line', source: 'plot', paint: { 'line-color': '#22c55e', 'line-width': 2 } })
      for (const c of ring) bounds.extend(c as [number, number])
    }
    for (const o of geoObs()) {
      const color = o.analysis ? sevColors[o.analysis.severity] ?? '#64748b' : '#64748b'
      const el = document.createElement('div')
      el.style.cssText = `width:16px;height:16px;border-radius:50%;border:2px solid #fff;box-shadow:0 0 0 1px rgba(0,0,0,.3);cursor:pointer;background:${color}`
      const html =
        (o.photoUrl ? `<img src="${o.photoUrl}" style="width:100%;border-radius:6px;margin-bottom:6px" />` : '') +
        `<div style="font-weight:600">${o.note ? escapeHtml(o.note) : '(sin nota)'}</div>` +
        (o.analysis ? `<div style="margin-top:4px;color:${color}">Severidad: ${sevLabels[o.analysis.severity] || o.analysis.severity}</div>` : '<div style="margin-top:4px;color:#64748b">Análisis IA en proceso…</div>')
      new maplibregl.Marker({ element: el })
        .setLngLat(o.location as [number, number])
        .setPopup(new maplibregl.Popup({ offset: 14 }).setHTML(`<div style="max-width:200px">${html}</div>`))
        .addTo(m)
      bounds.extend(o.location as [number, number])
    }
    if (!bounds.isEmpty()) m.fitBounds(bounds, { padding: 40, maxZoom: 17 })
    applyPlotRisk() // colorea el contorno si la agronomía ya está lista
  })
  incidentMap = m
}

function escapeHtml(s: string) {
  return s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c] as string))
}
async function loadAgronomy() {
  try {
    const ctx = await cyclesApi.agronomyContext(id)
    agronomy.value = await computeAgronomy(ctx)
    applyPlotRisk()
    if (ctx.lat != null && ctx.lng != null) loadWind(ctx.lat, ctx.lng)
  } catch { agronomy.value = null }
}

async function loadWind(lat: number, lng: number) {
  try {
    const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lng}`
      + `&current=wind_speed_10m,wind_direction_10m,wind_gusts_10m&timezone=auto`
    const c = (await (await fetch(url)).json()).current
    wind.value = { speed: c.wind_speed_10m ?? 0, dir: c.wind_direction_10m ?? 0, gust: c.wind_gusts_10m ?? 0 }
  } catch { wind.value = null }
}
const tasksByStage = ref<Record<string, WorkTask[]>>({})
const guideByStage = ref<Record<string, RecommendedTask[]>>({})
const team = ref<OrgUser[]>([])
const expanded = ref<string | null>(null)
const activeTab = ref('resumen')
// Las dos secciones de apoyo de la etapa arrancan plegadas: lo primero que el
// agrónomo necesita ver son sus tareas y sus costos.
const openGuide = ref(false)
const openAdvice = ref(false)

const closed = () => cycle.value?.status === 3
const currentStage = computed(() => cycle.value?.stages?.find((s) => s.id === expanded.value) ?? null)
// Etapas con el subtotal de costos como nota, para el stepper.
const stagesWithCost = computed(() =>
  (cycle.value?.stages ?? []).map((s) => {
    const sub = stageSubtotal(s.id)
    return { ...s, note: sub > 0 ? money(sub) : undefined }
  }),
)
const teamOptions = computed(() => [
  { label: '— sin asignar —', value: '' },
  ...team.value.map((u) => ({ label: u.fullName, value: u.id })),
])
const inputOptions = computed(() => [
  { label: '— manual —', value: '' },
  ...inputs.value.map((i) => ({ label: `${i.name} (${i.unit})`, value: i.id })),
])

// ---- Exportar reporte ----
function csvEscape(v: unknown) {
  const s = String(v ?? '')
  return /[",\n;]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s
}
function downloadCsv() {
  const r = report.value
  if (!r) return
  const rows: string[][] = [
    ['Reporte de ciclo'],
    ['Cultivo', r.crop + (r.variety ? ' · ' + r.variety : '')],
    ['Lote', r.plotName ?? '—'],
    ['Área (ha)', r.areaHa.toFixed(2)],
    ['Estado', cycleStatus[r.status]],
    [],
    ['Métrica', 'Valor'],
    ['Rendimiento (kg)', r.yieldKg.toFixed(0)],
    ['Rendimiento (kg/ha)', r.yieldPerHa.toFixed(1)],
    ['Costo total (L)', r.totalCost.toFixed(2)],
    ['Ingreso estimado (L)', r.revenueEst.toFixed(2)],
    ['Margen (L)', r.margin.toFixed(2)],
    ['Costo por kg (L)', r.costPerKg.toFixed(2)],
    ['Pérdida poscosecha (kg)', r.postHarvestLossKg.toFixed(0)],
    ['Pérdida (%)', r.lossPct.toFixed(1)],
    [],
    ['Costo por tipo', ''],
    ...r.costByKind.map((c) => [costKind[c.kind], c.total.toFixed(2)]),
    [],
    ['Costo por etapa', ''],
    ...r.costByStage.map((c) => [c.kind === null ? 'Sin etapa' : stageLabels[c.kind], c.total.toFixed(2)]),
  ]
  const csv = '﻿' + rows.map((row) => row.map(csvEscape).join(',')).join('\n')
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' })
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob)
  a.download = `reporte-${r.crop}.csv`
  a.click()
  URL.revokeObjectURL(a.href)
}
function printReport() {
  const r = report.value
  if (!r) return
  const row = (a: string, b: string) => `<tr><td>${a}</td><td style="text-align:right"><strong>${b}</strong></td></tr>`
  const kindRows = r.costByKind.map((c) => row(costKind[c.kind], money(c.total))).join('')
  const stageRows = r.costByStage.map((c) => row(c.kind === null ? 'Sin etapa' : stageLabels[c.kind], money(c.total))).join('')
  const html = `<!doctype html><html><head><meta charset="utf-8"><title>Reporte ${r.crop}</title>
    <style>
      body{font-family:system-ui,Segoe UI,Roboto,sans-serif;color:#1a1f1a;margin:40px}
      h1{color:#1f5a2a;margin:0 0 4px} .sub{color:#666;margin:0 0 20px}
      table{width:100%;border-collapse:collapse;margin:10px 0 24px}
      td,th{padding:7px 10px;border-bottom:1px solid #e6e9e3} th{text-align:left;color:#666;font-weight:600}
      .grid{display:grid;grid-template-columns:repeat(2,1fr);gap:8px 24px;margin-bottom:24px}
      .grid div{border-bottom:1px solid #eee;padding:6px 0;display:flex;justify-content:space-between}
      .muted{color:#666} h2{color:#1f5a2a;font-size:16px;margin:18px 0 4px}
    </style></head><body>
    <h1>${r.crop}${r.variety ? ' · ' + r.variety : ''}</h1>
    <p class="sub">${r.plotName ?? 'Lote'} · ${r.areaHa.toFixed(2)} ha · ${cycleStatus[r.status]}</p>
    <div class="grid">
      <div><span class="muted">Rendimiento</span><span><strong>${num(r.yieldKg)} kg</strong> (${r.yieldPerHa.toFixed(1)} kg/ha)</span></div>
      <div><span class="muted">Costo total</span><strong>${money(r.totalCost)}</strong></div>
      <div><span class="muted">Ingreso estimado</span><strong>${money(r.revenueEst)}</strong></div>
      <div><span class="muted">Margen</span><strong>${money(r.margin)}</strong></div>
      <div><span class="muted">Costo por kg</span><strong>${money(r.costPerKg, 2)}</strong></div>
      <div><span class="muted">Pérdida poscosecha</span><strong>${num(r.postHarvestLossKg)} kg (${r.lossPct.toFixed(1)}%)</strong></div>
    </div>
    <h2>Costo por tipo</h2><table>${kindRows || '<tr><td class="muted">Sin datos</td><td></td></tr>'}</table>
    <h2>Costo por etapa</h2><table>${stageRows || '<tr><td class="muted">Sin datos</td><td></td></tr>'}</table>
    </body></html>`
  const w = window.open('', '_blank')
  if (!w) return
  w.document.write(html)
  w.document.close()
  w.focus()
  w.print()
}

// Comparte un resumen del reporte por WhatsApp (wa.me abre el selector de contacto).
function shareWhatsApp() {
  const r = report.value
  if (!r) return
  const lines = [
    '*Reporte AgroApp*',
    `${r.crop}${r.variety ? ' · ' + r.variety : ''}`,
    `Lote: ${r.plotName ?? '—'} (${r.areaHa.toFixed(2)} ha)`,
    `Estado: ${cycleStatus[r.status]}`,
    `Rendimiento: ${num(r.yieldKg)} kg (${r.yieldPerHa.toFixed(1)} kg/ha)`,
    `Costo total: ${money(r.totalCost)}`,
    `Ingreso estimado: ${money(r.revenueEst)}`,
    `Margen: ${money(r.margin)}`,
    `Costo por kg: ${money(r.costPerKg, 2)}`,
  ]
  window.open(`https://wa.me/?text=${encodeURIComponent(lines.join('\n'))}`, '_blank')
}

// Formularios (uno a la vez: solo hay una etapa expandida).
const taskForm = ref({ title: '', description: '', assignedToUserId: '', dueDate: '' })
const costForm = ref({ kind: 1, inputId: '', description: '', quantity: 1, unitCost: 0 })
const phenoForm = ref({ recordedAt: '', stage: 0, plantHeightCm: null as number | null, pestIncidencePct: null as number | null, diseaseIncidencePct: null as number | null, notes: '' })
const closeForm = ref({ yieldKg: 0, quality: '', postHarvestLossKg: 0, revenueEst: 0, notes: '' })

onMounted(load)
async function load() {
  cycle.value = await cyclesApi.get(id)
  report.value = await cyclesApi.report(id)
  costs.value = await cyclesApi.costs(id)
  inputs.value = await inputsApi.list()
  try { phenology.value = await cyclesApi.phenology(id) } catch { phenology.value = [] }
  try { observations.value = await cyclesApi.observations(id) } catch { observations.value = [] }
  try { team.value = await usersApi.list() } catch { team.value = [] }
  if (cycle.value?.plotId) {
    try { plotPhotos.value = await cyclesApi.plotPhotos(cycle.value.plotId) } catch { plotPhotos.value = [] }
    try { profit.value = await cyclesApi.profitability(cycle.value.plotId) } catch { profit.value = null }
    try { fert.value = await cyclesApi.fertilization(cycle.value.plotId) } catch { fert.value = null }
    try { plot.value = await farmsApi.getPlot(cycle.value.plotId) } catch { plot.value = null }
  }
  await nextTick()
  loadAgronomy()
  // Selecciona la etapa actual (en progreso; si no, la primera sin completar).
  const stages = cycle.value?.stages ?? []
  if (!expanded.value && stages.length) {
    const current = stages.find((s) => s.status === 1) ?? stages.find((s) => s.status !== 2) ?? stages[0]
    await selectStage(current.id)
  }
}

// El mapa vive en una pestaña: se monta la primera vez que esa pestaña se abre.
async function onTabChange(value: string | number) {
  activeTab.value = String(value)
  if (activeTab.value === 'campo') {
    await nextTick()
    initIncidentMap()
  }
}

const sevLabels: Record<string, string> = { high: 'Alta', medium: 'Media', low: 'Baja', none: 'Sin incidencia' }
const sevColors: Record<string, string> = { high: '#dc2626', medium: '#ea580c', low: '#ca8a04', none: '#16a34a' }
function diagText(raw: string): string {
  const t = (raw ?? '').trim()
  if (t.startsWith('{')) {
    try { return String((JSON.parse(t) as { diagnosis?: string }).diagnosis ?? raw) } catch { /* keep */ }
  }
  return raw
}

async function selectStage(stageId: string) {
  expanded.value = stageId
  if (!tasksByStage.value[stageId]) tasksByStage.value[stageId] = await tasksApi.byStage(stageId)
  if (!guideByStage.value[stageId]) loadGuide(stageId)
}

function userName(userId: string | null) {
  return userId ? (team.value.find((u) => u.id === userId)?.fullName ?? '—') : null
}

async function refreshCosts() {
  costs.value = await cyclesApi.costs(id)
  report.value = await cyclesApi.report(id)
}

// --- Etapas ---
async function setStageStatus(stageId: string, status: number) {
  await cyclesApi.advanceStage(stageId, { status })
  cycle.value = await cyclesApi.get(id)
}

// --- Tareas ---
async function addTask(stageId: string) {
  if (!taskForm.value.title.trim()) return
  await tasksApi.create(stageId, {
    title: taskForm.value.title.trim(),
    description: taskForm.value.description || null,
    assignedToUserId: taskForm.value.assignedToUserId || null,
    dueDate: taskForm.value.dueDate || null,
  })
  taskForm.value = { title: '', description: '', assignedToUserId: '', dueDate: '' }
  tasksByStage.value[stageId] = await tasksApi.byStage(stageId)
}
/// Guion técnico de la etapa: tareas que el agrónomo debería cubrir.
async function loadGuide(stageId: string) {
  try { guideByStage.value[stageId] = await tasksApi.recommended(stageId) } catch { guideByStage.value[stageId] = [] }
}
async function addRecommended(stageId: string, rec: RecommendedTask) {
  await tasksApi.create(stageId, { title: rec.title, description: rec.description })
  tasksByStage.value[stageId] = await tasksApi.byStage(stageId)
  await loadGuide(stageId)
}
async function addAllRecommended(stageId: string) {
  const pending = (guideByStage.value[stageId] ?? []).filter((r) => !r.alreadyAdded)
  if (!pending.length) return
  for (const rec of pending) await tasksApi.create(stageId, { title: rec.title, description: rec.description })
  tasksByStage.value[stageId] = await tasksApi.byStage(stageId)
  await loadGuide(stageId)
  toast.add({ severity: 'success', summary: 'Tareas agregadas', detail: `Se crearon ${pending.length} tarea(s) en la etapa.`, life: 3500 })
}
const pendingGuide = (stageId: string) => (guideByStage.value[stageId] ?? []).filter((r) => !r.alreadyAdded).length

async function toggleTask(t: WorkTask) {
  await setTaskStatus(t, t.status === 2 ? 0 : 2)
}
async function setTaskStatus(t: WorkTask, status: number) {
  await tasksApi.setStatus(t.id, status)
  tasksByStage.value[t.stageId] = await tasksApi.byStage(t.stageId)
}
async function removeTask(t: WorkTask) {
  await tasksApi.remove(t.id)
  tasksByStage.value[t.stageId] = await tasksApi.byStage(t.stageId)
}

// --- Costos por etapa ---
function costsForStage(stageId: string) {
  return costs.value.filter((c) => c.stageId === stageId)
}
function stageSubtotal(stageId: string) {
  return costs.value.filter((c) => c.stageId === stageId).reduce((s, c) => s + c.total, 0)
}
function selectedInput() {
  return inputs.value.find((i) => i.id === costForm.value.inputId)
}
async function addCost(stageId: string) {
  if (!(costForm.value.quantity > 0)) { await alertDialog('La cantidad debe ser mayor que 0.'); return }
  if (!costForm.value.inputId && costForm.value.unitCost < 0) { await alertDialog('El costo unitario no puede ser negativo.'); return }
  await cyclesApi.addCost(id, {
    kind: costForm.value.kind,
    description: costForm.value.description || null,
    inputId: costForm.value.inputId || null,
    stageId,
    quantity: costForm.value.quantity,
    unitCost: costForm.value.inputId ? 0 : costForm.value.unitCost,
  })
  costForm.value = { kind: 1, inputId: '', description: '', quantity: 1, unitCost: 0 }
  await refreshCosts()
}
async function removeCost(costId: string) {
  if (!(await confirmDialog({ title: 'Eliminar costo', message: '¿Eliminar este costo?', danger: true, okText: 'Eliminar' }))) return
  await cyclesApi.removeCost(costId)
  await refreshCosts()
}
function inputName(inputId: string | null) {
  return inputId ? (inputs.value.find((i) => i.id === inputId)?.name ?? '—') : '—'
}
function stageNameOf(stageId: string | null) {
  const s = cycle.value?.stages?.find((x) => x.id === stageId)
  return s ? stageLabels[s.kind] : 'Sin etapa'
}

// --- Recomendaciones del análisis (etapas de planificación y preparación) ---
/// Pasa una enmienda recomendada al formulario de tareas para que quede programada.
function taskFromAmendment(am: AmendmentDose) {
  taskForm.value = {
    title: `${am.name}: ${num(am.totalKg)} kg de ${am.product}`,
    description: `${num(am.rateKgHa)} kg/ha · ${am.bags} quintales · ${am.timing}`,
    assignedToUserId: '',
    dueDate: '',
  }
  toast.add({
    severity: 'success',
    summary: 'Tarea preparada',
    detail: 'Revisa el formulario de tareas arriba y pulsa Agregar tarea.',
    life: 4000,
  })
}

// --- Monitoreo fenológico (etapa 5) ---
async function addPhenology() {
  if (!phenoForm.value.recordedAt) { await alertDialog('Indica la fecha del registro.'); return }
  await cyclesApi.addPhenology(id, {
    recordedAt: phenoForm.value.recordedAt, stage: phenoForm.value.stage,
    plantHeightCm: phenoForm.value.plantHeightCm, pestIncidencePct: phenoForm.value.pestIncidencePct,
    diseaseIncidencePct: phenoForm.value.diseaseIncidencePct, notes: phenoForm.value.notes || null,
  })
  phenoForm.value = { recordedAt: '', stage: 0, plantHeightCm: null, pestIncidencePct: null, diseaseIncidencePct: null, notes: '' }
  phenology.value = await cyclesApi.phenology(id)
}
async function removePhenology(recId: string) {
  if (!(await confirmDialog({ title: 'Eliminar registro', message: '¿Eliminar este registro de monitoreo?', danger: true, okText: 'Eliminar' }))) return
  await cyclesApi.removePhenology(recId)
  phenology.value = await cyclesApi.phenology(id)
}

// --- Cierre (etapa Evaluación) ---
async function closeCycle() {
  if (!(await confirmDialog({
    title: 'Cerrar ciclo',
    message: 'El ciclo quedará cerrado y sus datos pasarán a solo lectura. ¿Continuar?',
    okText: 'Cerrar ciclo',
  }))) return
  await cyclesApi.close(id, closeForm.value)
  await load()
}
</script>

<template>
  <div v-if="cycle && report">
    <PageHeader
      back
      :title="cycle.crop + (cycle.variety ? ' · ' + cycle.variety : '')"
      :subtitle="`${report.plotName ?? 'Lote'} · ${report.areaHa.toFixed(2)} ha`"
    >
      <template #actions>
        <Tag :value="cycleStatus[cycle.status]" :severity="cycleStatusSeverity[cycle.status]" />
        <Button label="CSV" icon="pi pi-download" severity="secondary" outlined size="small" @click="downloadCsv" />
        <Button label="PDF" icon="pi pi-print" severity="secondary" outlined size="small" @click="printReport" />
        <Button label="WhatsApp" icon="pi pi-whatsapp" severity="secondary" outlined size="small" @click="shareWhatsApp" />
      </template>
    </PageHeader>

    <!-- Cifras del ciclo, siempre visibles sobre las pestañas -->
    <div class="metrics">
      <div class="metric">
        <span>Rendimiento</span>
        <strong class="num">{{ num(report.yieldKg) }} kg</strong>
        <small class="tiny">{{ report.yieldPerHa.toFixed(1) }} kg/ha</small>
      </div>
      <div class="metric">
        <span>Costo total</span>
        <strong class="num">{{ money(report.totalCost) }}</strong>
        <small class="tiny">{{ money(report.costPerKg, 2) }} por kg</small>
      </div>
      <div class="metric">
        <span>Ingreso estimado</span>
        <strong class="num">{{ money(report.revenueEst) }}</strong>
      </div>
      <div class="metric">
        <span>Margen</span>
        <strong class="num" :class="report.margin >= 0 ? 'pos' : 'neg'">{{ money(report.margin) }}</strong>
      </div>
      <div class="metric">
        <span>Pérdida poscosecha</span>
        <strong class="num">{{ num(report.postHarvestLossKg) }} kg</strong>
        <small class="tiny">{{ report.lossPct.toFixed(1) }} % del total</small>
      </div>
    </div>

    <Tabs :value="activeTab" @update:value="onTabChange" class="cycle-tabs">
      <TabList>
        <PrimeTab value="resumen"><i class="pi pi-chart-bar" /> Resumen</PrimeTab>
        <PrimeTab value="etapas"><i class="pi pi-list-check" /> Etapas</PrimeTab>
        <PrimeTab value="costos"><i class="pi pi-wallet" /> Costos</PrimeTab>
        <PrimeTab value="campo"><i class="pi pi-map" /> Campo</PrimeTab>
      </TabList>

      <TabPanels>
        <!-- ============================ RESUMEN ============================ -->
        <TabPanel value="resumen">
          <div class="stack">
            <!-- Agronomía -->
            <SectionCard
              v-if="agronomy" title="Agronomía" icon="pi-sun"
              subtitle="Clima y suelo del cultivo según Open-Meteo."
            >
              <template #actions>
                <Button icon="pi pi-refresh" text rounded severity="secondary" aria-label="Recalcular" @click="loadAgronomy" />
              </template>

              <p v-if="agronomy.message" class="muted">{{ agronomy.message }}</p>
              <div v-else class="agro-grid">
                <div class="agro-box" v-if="agronomy.soil.length">
                  <div class="agro-title">Suelo por profundidad</div>
                  <div class="tiny">Lectura de la hora actual</div>
                  <table class="agro-soil">
                    <thead><tr><th>Prof.</th><th>Temp.</th><th>Humedad</th></tr></thead>
                    <tbody>
                      <tr v-for="l in agronomy.soil" :key="l.depthLabel">
                        <td>{{ l.depthLabel }}</td>
                        <td class="num">{{ l.tempC != null ? l.tempC.toFixed(1) + ' °C' : '—' }}</td>
                        <td class="num">{{ l.moisturePct != null ? l.moisturePct.toFixed(0) + ' %' : '—' }}</td>
                      </tr>
                    </tbody>
                  </table>
                </div>

                <div class="agro-box" v-if="agronomy.water">
                  <div class="agro-title">Riego (balance hídrico)</div>
                  <div class="tiny">Últimos 7 días + 7 de pronóstico</div>
                  <div v-if="agronomy.water.kc" class="agro-line">
                    Kc <strong>{{ agronomy.water.kc.toFixed(2) }}</strong>
                    <span class="muted">({{ agronomy.water.kcStage }})</span> ·
                    ETc <strong>{{ agronomy.water.etcMm7d?.toFixed(1) }} mm</strong>
                  </div>
                  <div class="agro-line">ET0 <strong>{{ agronomy.water.et0Mm7d.toFixed(1) }} mm</strong> · Lluvia <strong>{{ agronomy.water.precipMm7d.toFixed(1) }} mm</strong></div>
                  <div class="agro-line">Déficit <strong>{{ agronomy.water.deficitMm.toFixed(1) }} mm</strong></div>
                  <Tag
                    :value="agronomy.water.irrigationSuggested ? `Riego recomendado ~${agronomy.water.suggestedMm.toFixed(0)} mm` : 'Sin déficit relevante'"
                    :severity="agronomy.water.irrigationSuggested ? 'warn' : 'success'" class="agro-tag"
                  />
                  <div v-if="agronomy.water.irrigationSuggested && agronomy.water.volumeM3" class="agro-line">
                    Volumen <strong>{{ num(agronomy.water.volumeM3) }} m³</strong>
                    <span v-if="caudal > 0"> · ~<strong>{{ (agronomy.water.volumeM3 / caudal).toFixed(1) }} h</strong></span>
                  </div>
                  <div v-if="agronomy.water.irrigationSuggested" class="caudal">
                    <span class="muted">Caudal</span>
                    <InputNumber
                      :model-value="caudal" :min="1" :max-fraction-digits="0" size="small" input-class="caudal-input"
                      @update:model-value="setCaudal(Number($event))"
                    />
                    <span class="muted">m³/h</span>
                  </div>
                </div>

                <div class="agro-box" v-if="agronomy.gdd && agronomy.gdd.days > 0">
                  <div class="agro-title">Grados-día (GDD)</div>
                  <div class="tiny">Desde el inicio del ciclo</div>
                  <div class="agro-big num">{{ num(agronomy.gdd.accumulated) }} <small>°C·día</small></div>
                  <div class="muted">Base {{ agronomy.gdd.baseTempC }} °C · {{ agronomy.gdd.days }} días acumulados</div>
                </div>

                <div class="agro-box" v-if="agronomy.disease">
                  <div class="agro-title">Riesgo de enfermedad</div>
                  <div class="tiny">Últimas 48 h</div>
                  <span class="badge agro-tag" :style="{ background: sevColors[agronomy.disease.level] + '22', color: sevColors[agronomy.disease.level] }">
                    {{ diseaseLabels[agronomy.disease.level] || agronomy.disease.level }}
                  </span>
                  <div class="tiny reason">{{ agronomy.disease.reason }}</div>
                </div>
              </div>
            </SectionCard>

            <!-- Rentabilidad del lote -->
            <SectionCard
              v-if="profit && profit.cycles.length" title="Rentabilidad del lote" icon="pi-chart-line"
              :subtitle="`${profit.plotName ?? ''} · ${profit.areaHa.toFixed(2)} ha · ${profit.seasons} temporada(s)`"
            >
              <div class="metrics inner">
                <div class="metric"><span>Margen acumulado</span><strong class="num" :class="profit.totalMargin >= 0 ? 'pos' : 'neg'">{{ money(profit.totalMargin) }}</strong></div>
                <div class="metric"><span>Rendimiento promedio</span><strong class="num">{{ profit.avgYieldPerHa.toFixed(1) }} kg/ha</strong></div>
                <div class="metric"><span>Costo promedio</span><strong class="num">{{ money(profit.avgCostPerKg, 2) }} / kg</strong></div>
              </div>
              <DataTable :value="profit.cycles" size="small" class="mt" :row-class="(r: any) => r.cycleId === id ? 'row-current' : ''">
                <Column header="Temporada">
                  <template #body="{ data }">
                    <strong>{{ data.crop }}</strong><span v-if="data.variety" class="muted"> · {{ data.variety }}</span>
                    <div class="tiny">{{ data.start ?? '—' }}</div>
                  </template>
                </Column>
                <Column header="Estado"><template #body="{ data }">{{ cycleStatus[data.status] }}</template></Column>
                <Column header="Rend." ><template #body="{ data }"><span class="num">{{ num(data.yieldKg) }} kg</span></template></Column>
                <Column header="kg/ha"><template #body="{ data }"><span class="num">{{ data.yieldPerHa.toFixed(1) }}</span></template></Column>
                <Column header="Costo"><template #body="{ data }"><span class="num">{{ money(data.totalCost) }}</span></template></Column>
                <Column header="Ingreso"><template #body="{ data }"><span class="num">{{ money(data.revenueEst) }}</span></template></Column>
                <Column header="Margen">
                  <template #body="{ data }"><span class="num" :class="data.margin >= 0 ? 'pos' : 'neg'">{{ money(data.margin) }}</span></template>
                </Column>
                <Column header="L/kg"><template #body="{ data }"><span class="num">{{ money(data.costPerKg, 2) }}</span></template></Column>
              </DataTable>
            </SectionCard>

            <!-- Plan de fertilización -->
            <SectionCard
              v-if="fert && fert.hasAnalysis" title="Plan de fertilización" icon="pi-inbox"
              :subtitle="'Según el análisis de suelo' + (fert.sampledAt ? ' del ' + fert.sampledAt : '')"
            >
              <DataTable :value="fert.items" size="small">
                <Column field="nutrient" header="Nutriente">
                  <template #body="{ data }"><strong>{{ data.nutrient }}</strong></template>
                </Column>
                <Column header="Valor">
                  <template #body="{ data }">
                    <span class="num">{{ data.value != null ? data.value + (data.unit ? ' ' + data.unit : '') : '—' }}</span>
                  </template>
                </Column>
                <Column header="Estado">
                  <template #body="{ data }">
                    <span class="badge" :style="{ background: fertColors[data.status] + '22', color: fertColors[data.status] }">
                      {{ fertLabels[data.status] || data.status }}
                    </span>
                  </template>
                </Column>
                <Column field="recommendation" header="Recomendación" />
              </DataTable>

              <template v-if="fert.recipe && fert.recipe.doses.length">
                <h4 class="sub-h">
                  Receta orientativa
                  <span class="muted">· meta {{ fert.recipe.targetYieldTonHa }} t/ha sobre {{ fert.recipe.areaHa.toFixed(2) }} ha</span>
                </h4>
                <DataTable :value="fert.recipe.doses" size="small">
                  <Column field="nutrient" header="Nutriente"><template #body="{ data }"><strong>{{ data.nutrient }}</strong></template></Column>
                  <Column header="Dosis"><template #body="{ data }"><span class="num">{{ data.doseKgHa }} kg/ha</span></template></Column>
                  <Column header="Producto">
                    <template #body="{ data }">{{ data.product }}<div class="tiny num">{{ data.productKgHa }} kg/ha</div></template>
                  </Column>
                  <Column header="Cantidad lote"><template #body="{ data }"><span class="num">{{ num(data.totalKg) }} kg</span></template></Column>
                  <Column header="Bultos"><template #body="{ data }"><span class="num">{{ data.bags }}</span></template></Column>
                  <Column header="Costo est."><template #body="{ data }"><span class="num">{{ money(data.estCost) }}</span></template></Column>
                </DataTable>
                <p class="total-line">Total estimado <strong class="num">{{ money(fert.recipe.totalCost) }}</strong></p>
                <p class="tiny">{{ fert.recipe.note }}</p>
              </template>
              <p class="tiny">{{ fert.note }}</p>
            </SectionCard>
          </div>
        </TabPanel>

        <!-- ============================ ETAPAS ============================= -->
        <TabPanel value="etapas">
          <SectionCard
            title="Etapas del ciclo" icon="pi-list-check"
            subtitle="Elige una etapa para gestionar sus tareas, costos y registros."
          >
            <StageProgress
              :stages="stagesWithCost" :active-id="expanded" interactive
              @select="selectStage"
            />
          </SectionCard>

          <SectionCard
            v-if="currentStage" class="mt" :title="stageLabels[currentStage.kind]" icon="pi-folder-open"
          >
            <template #actions>
              <span class="muted">Estado</span>
              <Select
                :model-value="currentStage.status" :options="stageStatusOptions" option-label="label" option-value="value"
                :disabled="closed()" size="small" class="w-160"
                @update:model-value="setStageStatus(currentStage!.id, $event)"
              />
            </template>

            <!-- Tareas -->
            <h4 class="sub-h first">Tareas</h4>
            <EmptyState v-if="!(tasksByStage[currentStage.id] || []).length" icon="pi-check-square" text="Sin tareas en esta etapa." />
            <ul v-else class="tasks">
              <li v-for="t in tasksByStage[currentStage.id]" :key="t.id">
                <Checkbox :model-value="t.status === 2" binary :disabled="closed()" @update:model-value="toggleTask(t)" />
                <div class="task-text">
                  <span :class="{ done: t.status === 2 }">{{ t.title }}</span>
                  <small v-if="t.description" class="muted">{{ t.description }}</small>
                  <small class="tiny">
                    <template v-if="userName(t.assignedToUserId)"><i class="pi pi-user" /> {{ userName(t.assignedToUserId) }}</template>
                    <template v-if="t.dueDate"> · <i class="pi pi-calendar" /> {{ t.dueDate }}</template>
                  </small>
                </div>
                <Select
                  :model-value="t.status" :options="taskStatusOptions" option-label="label" option-value="value"
                  :disabled="closed()" size="small" class="w-140"
                  @update:model-value="setTaskStatus(t, $event)"
                />
                <Button icon="pi pi-trash" text rounded severity="danger" :disabled="closed()" aria-label="Eliminar" @click="removeTask(t)" />
              </li>
            </ul>

            <div v-if="!closed()" class="form-box mt">
              <div class="field-row">
                <label class="field"><span>Título</span><InputText v-model="taskForm.title" placeholder="Ej. Fertilizar el lote" @keyup.enter="addTask(currentStage!.id)" /></label>
                <label class="field"><span>Descripción</span><InputText v-model="taskForm.description" /></label>
                <label class="field"><span>Responsable</span>
                  <Select v-model="taskForm.assignedToUserId" :options="teamOptions" option-label="label" option-value="value" />
                </label>
                <label class="field"><span>Fecha límite</span><InputText v-model="taskForm.dueDate" type="date" /></label>
                <Button label="Agregar tarea" icon="pi pi-plus" @click="addTask(currentStage!.id)" />
              </div>
            </div>

            <!-- Guion técnico de la etapa -->
            <div class="sub-h">
              <button class="disclosure" :aria-expanded="openGuide" @click="openGuide = !openGuide">
                <i :class="['pi', openGuide ? 'pi-chevron-down' : 'pi-chevron-right']" />
                Tareas recomendadas
                <span class="muted">· lo que suele cubrirse en esta etapa</span>
                <Tag
                  v-if="pendingGuide(currentStage.id)" :value="`${pendingGuide(currentStage.id)} sin agregar`"
                  severity="secondary"
                />
              </button>
              <span style="flex:1" />
              <Button
                v-if="openGuide && pendingGuide(currentStage.id) > 1" :label="`Agregar las ${pendingGuide(currentStage.id)} pendientes`"
                icon="pi pi-plus" link size="small" :disabled="closed()" @click="addAllRecommended(currentStage!.id)"
              />
            </div>
            <ul v-show="openGuide" class="guide">
              <li v-for="rec in guideByStage[currentStage.id] || []" :key="rec.title" :class="{ done: rec.alreadyAdded }">
                <i :class="['pi', rec.alreadyAdded ? 'pi-check-circle' : 'pi-circle']" />
                <div>
                  <strong>{{ rec.title }}</strong>
                  <p>{{ rec.description }}</p>
                </div>
                <Button
                  v-if="!rec.alreadyAdded" label="Agregar" icon="pi pi-plus" size="small" outlined
                  :disabled="closed()" @click="addRecommended(currentStage!.id, rec)"
                />
                <span v-else class="tiny added">En el tablero</span>
              </li>
            </ul>

            <!-- Recomendaciones del análisis (Planificación / Prep. suelo) -->
            <template v-if="currentStage.kind === 0 || currentStage.kind === 1">
              <div class="sub-h">
                <button class="disclosure" :aria-expanded="openAdvice" @click="openAdvice = !openAdvice">
                  <i :class="['pi', openAdvice ? 'pi-chevron-down' : 'pi-chevron-right']" />
                  Recomendaciones del análisis
                  <span v-if="fert?.sampledAt" class="muted">· muestra de suelo del {{ fert.sampledAt }}</span>
                  <Tag
                    v-if="fert?.amendments?.length" :value="`${fert.amendments.length} enmienda(s)`"
                    severity="warn"
                  />
                </button>
                <span style="flex:1" />
                <Button
                  v-if="openAdvice" label="Ver y registrar análisis" icon="pi pi-arrow-right" icon-pos="right" link size="small"
                  @click="router.push({ name: 'analyses', params: { id: cycle!.plotId }, query: { name: report?.plotName ?? 'Lote' } })"
                />
              </div>

              <div v-show="openAdvice">
              <Message v-if="!fert || (!fert.hasAnalysis && !fert.hasWaterAnalysis)" severity="info" :closable="false">
                Registra un análisis de suelo o de agua del lote y aquí aparecerán las enmiendas recomendadas,
                con la dosis y el costo ya calculados para las {{ report.areaHa.toFixed(2) }} ha del lote.
              </Message>

              <template v-else>
                <!-- Qué dice el análisis -->
                <ul class="diag">
                  <li v-for="it in fert.items" :key="it.nutrient">
                    <span class="badge" :style="{ background: fertColors[it.status] + '22', color: fertColors[it.status] }">
                      {{ fertLabels[it.status] || it.status }}
                    </span>
                    <div>
                      <strong>{{ it.nutrient }}</strong>
                      <span v-if="it.value != null" class="num muted"> · {{ it.value }}{{ it.unit ? ' ' + it.unit : '' }}</span>
                      <p>{{ it.recommendation }}</p>
                    </div>
                  </li>
                  <li v-for="it in fert.waterItems" :key="it.parameter">
                    <span class="badge" :style="{ background: fertColors[it.status] + '22', color: fertColors[it.status] }">
                      {{ fertLabels[it.status] || it.status }}
                    </span>
                    <div>
                      <strong>{{ it.parameter }}</strong>
                      <span v-if="it.value != null" class="num muted"> · {{ it.value }}{{ it.unit ? ' ' + it.unit : '' }}</span>
                      <p>{{ it.recommendation }}</p>
                    </div>
                  </li>
                </ul>

                <!-- Qué hacer, con dosis -->
                <template v-if="fert.amendments.length">
                  <h5 class="amend-h">Enmiendas para este lote</h5>
                  <div class="amend-grid">
                    <article v-for="am in fert.amendments" :key="am.name" class="amend">
                      <header><i class="pi pi-sparkles" /> {{ am.name }}</header>
                      <p class="amend-dose">
                        <strong class="num">{{ num(am.rateKgHa) }} kg/ha</strong> de {{ am.product }}
                      </p>
                      <dl>
                        <div><dt>Para el lote</dt><dd class="num">{{ num(am.totalKg) }} kg · {{ am.bags }} qq</dd></div>
                        <div><dt>Costo estimado</dt><dd class="num">{{ money(am.estCost) }}</dd></div>
                        <div><dt>Cuándo</dt><dd>{{ am.timing }}</dd></div>
                      </dl>
                      <p class="tiny reason">{{ am.reason }}</p>
                      <Button
                        label="Programar como tarea" icon="pi pi-calendar-plus" size="small" outlined
                        :disabled="closed()" @click="taskFromAmendment(am)"
                      />
                    </article>
                  </div>
                </template>
                <Message v-else-if="fert.hasAnalysis" severity="success" :closable="false">
                  El análisis no exige enmiendas: el pH y la materia orgánica están dentro del rango del cultivo.
                </Message>

                <p class="tiny">
                  Dosis orientativas calculadas con la textura del suelo y el pH objetivo del cultivo. Confírmalas con tu
                  laboratorio antes de comprar.
                </p>
              </template>
              </div>
            </template>

            <!-- Monitoreo fenológico -->
            <template v-if="currentStage.kind === 4">
              <h4 class="sub-h">Monitoreo fenológico</h4>
              <div v-if="!closed()" class="form-box">
                <div class="field-row">
                  <label class="field"><span>Fecha</span><InputText v-model="phenoForm.recordedAt" type="date" /></label>
                  <label class="field"><span>Etapa</span>
                    <Select v-model="phenoForm.stage" :options="phenoStageOptions" option-label="label" option-value="value" />
                  </label>
                  <label class="field"><span>Altura (cm)</span><InputNumber v-model="phenoForm.plantHeightCm" :max-fraction-digits="1" /></label>
                  <label class="field"><span>Plagas (%)</span><InputNumber v-model="phenoForm.pestIncidencePct" :max-fraction-digits="1" /></label>
                  <label class="field"><span>Enfermedad (%)</span><InputNumber v-model="phenoForm.diseaseIncidencePct" :max-fraction-digits="1" /></label>
                  <label class="field"><span>Notas</span><InputText v-model="phenoForm.notes" /></label>
                  <Button label="Registrar" icon="pi pi-plus" @click="addPhenology" />
                </div>
              </div>
              <DataTable :value="phenology" size="small" class="mt">
                <template #empty><EmptyState icon="pi-chart-line" text="Sin registros de monitoreo." /></template>
                <Column field="recordedAt" header="Fecha" />
                <Column header="Etapa"><template #body="{ data }">{{ phenoStages[data.stage] }}</template></Column>
                <Column header="Altura"><template #body="{ data }"><span class="num">{{ data.plantHeightCm ?? '—' }}</span></template></Column>
                <Column header="Plagas %"><template #body="{ data }"><span class="num">{{ data.pestIncidencePct ?? '—' }}</span></template></Column>
                <Column header="Enf. %"><template #body="{ data }"><span class="num">{{ data.diseaseIncidencePct ?? '—' }}</span></template></Column>
                <Column field="notes" header="Notas" />
                <Column style="width:3rem">
                  <template #body="{ data }">
                    <Button icon="pi pi-trash" text rounded severity="danger" aria-label="Eliminar" @click="removePhenology(data.id)" />
                  </template>
                </Column>
              </DataTable>
            </template>

            <!-- Costos de la etapa -->
            <h4 class="sub-h">
              Costos de la etapa
              <span v-if="stageSubtotal(currentStage.id) > 0" class="muted">· subtotal {{ money(stageSubtotal(currentStage.id)) }}</span>
            </h4>
            <div v-if="!closed()" class="form-box">
              <div class="field-row">
                <label class="field"><span>Tipo</span>
                  <Select v-model="costForm.kind" :options="costKindOptions" option-label="label" option-value="value" />
                </label>
                <label class="field"><span>Insumo</span>
                  <Select v-model="costForm.inputId" :options="inputOptions" option-label="label" option-value="value" />
                </label>
                <label class="field"><span>Cantidad</span><InputNumber v-model="costForm.quantity" :max-fraction-digits="2" /></label>
                <label v-if="!costForm.inputId" class="field"><span>Costo unitario</span>
                  <InputNumber v-model="costForm.unitCost" :max-fraction-digits="2" />
                </label>
                <label v-else class="field"><span>Costo unitario</span>
                  <span class="readonly num">{{ money(selectedInput()?.unitCost ?? 0, 2) }}</span>
                </label>
                <label class="field"><span>Descripción</span><InputText v-model="costForm.description" /></label>
                <Button label="Agregar" icon="pi pi-plus" @click="addCost(currentStage!.id)" />
              </div>
            </div>
            <DataTable :value="costsForStage(currentStage.id)" size="small" class="mt">
              <template #empty><EmptyState icon="pi-wallet" text="Sin costos en esta etapa." /></template>
              <Column header="Tipo"><template #body="{ data }">{{ costKind[data.kind] }}</template></Column>
              <Column header="Insumo"><template #body="{ data }">{{ inputName(data.inputId) }}</template></Column>
              <Column field="description" header="Descripción" />
              <Column header="Cant."><template #body="{ data }"><span class="num">{{ num(data.quantity, 2) }}</span></template></Column>
              <Column header="Total"><template #body="{ data }"><strong class="num">{{ money(data.total) }}</strong></template></Column>
              <Column style="width:3rem">
                <template #body="{ data }">
                  <Button icon="pi pi-trash" text rounded severity="danger" :disabled="closed()" aria-label="Eliminar" @click="removeCost(data.id)" />
                </template>
              </Column>
            </DataTable>

            <!-- Cierre del ciclo -->
            <template v-if="currentStage.kind === 7">
              <h4 class="sub-h">Cierre de cosecha</h4>
              <div v-if="!closed()">
                <div class="form-box">
                  <div class="field-row">
                    <label class="field"><span>Rendimiento (kg)</span><InputNumber v-model="closeForm.yieldKg" /></label>
                    <label class="field"><span>Pérdida poscosecha (kg)</span><InputNumber v-model="closeForm.postHarvestLossKg" /></label>
                    <label class="field"><span>Ingreso estimado (L)</span><InputNumber v-model="closeForm.revenueEst" /></label>
                    <label class="field"><span>Calidad</span><InputText v-model="closeForm.quality" /></label>
                    <label class="field grow"><span>Notas</span><InputText v-model="closeForm.notes" /></label>
                  </div>
                </div>
                <Button label="Cerrar ciclo" icon="pi pi-lock" class="mt" @click="closeCycle" />
              </div>
              <p v-else class="muted">Ciclo cerrado con un rendimiento de {{ num(cycle.yieldKg ?? 0) }} kg.</p>
            </template>
          </SectionCard>
        </TabPanel>

        <!-- ============================ COSTOS ============================= -->
        <TabPanel value="costos">
          <div class="stack">
            <div class="grid-2">
              <SectionCard title="Costo por tipo" icon="pi-chart-pie">
                <EmptyState v-if="!report.costByKind.length" icon="pi-wallet" text="Sin costos registrados." />
                <div v-for="s in report.costByKind" :key="s.kind" class="bar-item">
                  <div class="bar-head"><span>{{ costKind[s.kind] }}</span><strong class="num">{{ money(s.total) }}</strong></div>
                  <div class="bar"><span :style="{ width: (report.totalCost ? s.total / report.totalCost * 100 : 0) + '%' }" /></div>
                </div>
              </SectionCard>

              <SectionCard title="Costo por etapa" icon="pi-chart-bar">
                <EmptyState v-if="!report.costByStage.length" icon="pi-wallet" text="Todavía no hay costos por etapa." />
                <div v-for="(cs, i) in report.costByStage" :key="i" class="bar-item">
                  <div class="bar-head">
                    <span>{{ cs.kind === null ? 'Sin etapa' : stageLabels[cs.kind] }}</span>
                    <strong class="num">{{ money(cs.total) }}</strong>
                  </div>
                  <div class="bar"><span :style="{ width: (report.totalCost ? cs.total / report.totalCost * 100 : 0) + '%' }" /></div>
                </div>
              </SectionCard>
            </div>

            <SectionCard
              title="Todos los costos del ciclo" icon="pi-list"
              :subtitle="`${costs.length} movimiento(s) · ${money(report.totalCost)} en total`" flush
            >
              <DataTable :value="costs" size="small" paginator :rows="12" removable-sort>
                <template #empty><EmptyState icon="pi-wallet" text="Sin costos registrados en este ciclo." /></template>
                <Column header="Fecha" sortable field="incurredAt">
                  <template #body="{ data }">{{ shortDate(data.incurredAt) }}</template>
                </Column>
                <Column header="Etapa"><template #body="{ data }">{{ stageNameOf(data.stageId) }}</template></Column>
                <Column header="Tipo"><template #body="{ data }">{{ costKind[data.kind] }}</template></Column>
                <Column header="Insumo"><template #body="{ data }">{{ inputName(data.inputId) }}</template></Column>
                <Column field="description" header="Descripción" />
                <Column header="Cant."><template #body="{ data }"><span class="num">{{ num(data.quantity, 2) }}</span></template></Column>
                <Column header="Unitario"><template #body="{ data }"><span class="num">{{ money(data.unitCost, 2) }}</span></template></Column>
                <Column header="Total" sortable field="total">
                  <template #body="{ data }"><strong class="num">{{ money(data.total) }}</strong></template>
                </Column>
                <Column style="width:3rem">
                  <template #body="{ data }">
                    <Button icon="pi pi-trash" text rounded severity="danger" :disabled="closed()" aria-label="Eliminar" @click="removeCost(data.id)" />
                  </template>
                </Column>
              </DataTable>
            </SectionCard>
          </div>
        </TabPanel>

        <!-- ============================= CAMPO ============================= -->
        <TabPanel value="campo">
          <div class="stack">
            <SectionCard
              v-if="mapToken" title="Mapa del lote" icon="pi-map"
              :subtitle="`${geoObs().length} incidente(s) geolocalizado(s)`"
            >
              <div class="map-wrap">
                <div ref="mapEl" class="inc-map" />
                <div class="map-hud" v-if="agronomy || wind">
                  <div class="hud-row" v-if="agronomy">
                    <span class="hud-dot" :style="{ background: plotRisk().color }" />
                    <span>Estado del lote: <strong>{{ plotRisk().label }}</strong></span>
                  </div>
                  <div class="hud-row" v-if="wind">
                    <span class="hud-arrow" :style="{ transform: `rotate(${wind.dir + 180}deg)` }">↑</span>
                    <span>Viento <strong>{{ Math.round(wind.speed) }} km/h</strong><span v-if="wind.gust > wind.speed + 3" class="muted"> · ráfagas {{ Math.round(wind.gust) }}</span></span>
                  </div>
                  <div class="hud-row" v-if="drift()">
                    <span class="hud-dot" :style="{ background: drift()!.color }" />
                    <span>Aspersión: <strong :style="{ color: drift()!.color }">{{ drift()!.label }}</strong></span>
                  </div>
                </div>
              </div>
              <p class="tiny map-note">
                Cada pin es una observación, coloreada por la severidad que detectó la IA. El contorno del lote refleja
                su estado agronómico y el recuadro resume viento y aptitud para aspersión.
              </p>
            </SectionCard>

            <SectionCard
              title="Observaciones con análisis IA" icon="pi-camera"
              :subtitle="`${observations.length} observación(es) de este ciclo`"
            >
              <EmptyState
                v-if="!observations.length" icon="pi-camera" text="Sin observaciones."
                hint="Se registran desde la app móvil tomando una foto de la planta."
              />
              <div v-else class="obs-grid">
                <article v-for="o in observations" :key="o.id" class="obs-card">
                  <img v-if="o.photoUrl" :src="o.photoUrl" class="obs-img" loading="lazy" />
                  <div class="obs-body">
                    <div class="obs-note">{{ o.note || '(sin nota)' }}</div>
                    <div v-if="!o.analysis" class="tiny">Análisis IA en proceso…</div>
                    <template v-else>
                      <div class="obs-sev-row">
                        <span class="badge" :style="{ background: sevColors[o.analysis.severity] + '22', color: sevColors[o.analysis.severity] }">
                          Severidad {{ sevLabels[o.analysis.severity] || '—' }}
                        </span>
                        <span class="tiny">Confianza {{ Math.round((o.analysis.confidence ?? 0) * 100) }} %</span>
                      </div>
                      <p class="obs-diag">{{ diagText(o.analysis.diagnosis) }}</p>
                      <p v-if="o.analysis.recommendations" class="obs-reco">
                        <strong>Recomendaciones:</strong> {{ o.analysis.recommendations }}
                      </p>
                    </template>
                  </div>
                </article>
              </div>
            </SectionCard>

            <SectionCard
              v-if="plotPhotos.length" title="Historial visual del lote" icon="pi-images"
              :subtitle="`${plotPhotos.length} foto(s) de todos los ciclos de este lote`"
            >
              <div class="gal-grid">
                <figure class="gal" v-for="p in plotPhotos" :key="p.id">
                  <a :href="p.photoUrl" target="_blank" rel="noopener"><img :src="p.photoUrl" loading="lazy" /></a>
                  <figcaption>
                    <strong>{{ shortDate(p.createdAt) }}</strong> · {{ p.crop }}
                    <span v-if="p.analysis" class="badge sm" :style="{ background: sevColors[p.analysis.severity] + '22', color: sevColors[p.analysis.severity] }">
                      {{ sevLabels[p.analysis.severity] || p.analysis.severity }}
                    </span>
                    <div v-if="p.note" class="tiny">{{ p.note }}</div>
                  </figcaption>
                </figure>
              </div>
            </SectionCard>
          </div>
        </TabPanel>
      </TabPanels>
    </Tabs>
  </div>

  <div v-else class="muted">Cargando ciclo…</div>
</template>

<style scoped>
/* Cifras del encabezado */
.metrics {
  display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 1px;
  background: var(--border); border: 1px solid var(--border); border-radius: 14px; overflow: hidden; margin-bottom: 20px;
}
.metrics .metric { background: var(--surface); padding: 14px 16px; display: flex; flex-direction: column; gap: 2px; }
.metrics .metric > span { font-size: 12.5px; color: var(--muted); font-weight: 600; }
.metrics .metric strong { font-size: 19px; font-weight: 800; letter-spacing: -.02em; }
.metrics.inner { margin-bottom: 16px; }

.cycle-tabs :deep(.p-tab) { display: flex; align-items: center; gap: 8px; font-weight: 600; }
.cycle-tabs :deep(.p-tabpanels) { background: transparent; padding: 20px 0 0; }
.cycle-tabs :deep(.p-tablist-tab-list) { background: transparent; }

.mt { margin-top: 16px; }
.w-140 { width: 140px; }
.w-150 { width: 150px; }
.w-160 { width: 160px; }
.grow { flex: 2; min-width: 180px; }
.readonly { padding: 8px 0; font-weight: 600; }

.sub-h { font-size: 14px; font-weight: 700; margin: 24px 0 10px; display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.sub-h.first { margin-top: 0; }
.disclosure {
  display: flex; align-items: center; gap: 8px; flex-wrap: wrap; background: none; border: none;
  padding: 0; margin: 0; font: inherit; font-size: 14px; font-weight: 700; color: inherit; cursor: pointer;
}
.disclosure > i { font-size: 12px; color: var(--muted); transition: color .15s; }
.disclosure:hover > i { color: var(--leaf); }
.disclosure .muted { font-weight: 400; }
.sub-h .muted { font-weight: 400; }
.total-line { text-align: right; margin: 10px 0 0; font-size: 14px; }
.total-line strong { margin-left: 8px; }

.badge { display: inline-block; padding: 3px 10px; border-radius: 999px; font-size: 12px; font-weight: 600; }

/* Guion técnico de la etapa */
.guide { list-style: none; margin: 0; padding: 0; }
.guide li { display: flex; align-items: flex-start; gap: 11px; padding: 11px 0; border-bottom: 1px solid var(--border); }
.guide li:last-child { border-bottom: none; }
.guide li > i { font-size: 15px; color: #b9c2b6; margin-top: 2px; }
.guide li.done > i { color: var(--leaf); }
.guide li.done strong { color: var(--muted); }
.guide li > div { flex: 1; min-width: 0; }
.guide p { margin: 2px 0 0; font-size: 13px; color: var(--muted); line-height: 1.5; }
.guide .added { color: var(--leaf); font-weight: 600; white-space: nowrap; padding-top: 4px; }

/* Recomendaciones del análisis */
.diag { list-style: none; margin: 0 0 18px; padding: 0; }
.diag li { display: flex; align-items: flex-start; gap: 10px; padding: 10px 0; border-bottom: 1px solid var(--border); }
.diag li:last-child { border-bottom: none; }
.diag li .badge { flex-shrink: 0; min-width: 74px; text-align: center; }
.diag p { margin: 3px 0 0; font-size: 13.5px; color: var(--muted); line-height: 1.5; }
.amend-h { font-size: 13px; font-weight: 700; text-transform: uppercase; letter-spacing: .05em; color: var(--muted); margin: 0 0 10px; }
.amend-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 12px; }
.amend { border: 1px solid var(--border); border-radius: 12px; padding: 14px; background: #f7f9f5; }
.amend header { display: flex; align-items: center; gap: 8px; font-weight: 700; font-size: 14.5px; }
.amend header i { color: var(--leaf); }
.amend-dose { margin: 10px 0; font-size: 14px; }
.amend-dose strong { font-size: 17px; }
.amend dl { margin: 0 0 10px; font-size: 13px; }
.amend dl > div { display: flex; justify-content: space-between; gap: 10px; padding: 3px 0; border-bottom: 1px dashed var(--border); }
.amend dl > div:last-child { border-bottom: none; }
.amend dt { color: var(--muted); }
.amend dd { margin: 0; font-weight: 600; text-align: right; }
.amend .reason { line-height: 1.5; margin: 0 0 12px; }
.badge.sm { font-size: 11px; padding: 1px 7px; margin-left: 4px; }

/* Tareas */
.tasks { list-style: none; margin: 0; padding: 0; }
.tasks li { display: flex; align-items: flex-start; gap: 11px; padding: 10px 0; border-bottom: 1px solid var(--border); }
.tasks li:last-child { border-bottom: none; }
.task-text { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px; }
.task-text > span { font-weight: 600; }
.task-text > span.done { text-decoration: line-through; color: var(--muted); }

/* Agronomía */
.agro-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(210px, 1fr)); gap: 12px; }
.agro-box { border: 1px solid var(--border); border-radius: 12px; padding: 12px; background: #fbfcfa; }
.agro-title { font-weight: 700; font-size: 13.5px; }
.agro-line { font-size: 13.5px; margin-top: 4px; }
.agro-big { font-size: 26px; font-weight: 800; margin-top: 6px; }
.agro-big small { font-size: 13px; color: var(--muted); font-weight: 600; }
.agro-tag { margin-top: 8px; }
.agro-soil { width: 100%; font-size: 13px; margin-top: 6px; border-collapse: collapse; }
.agro-soil th { text-align: left; color: var(--muted); font-weight: 600; font-size: 11.5px; }
.agro-soil td { padding: 2px 0; }
.reason { margin-top: 6px; }
.caudal { display: flex; align-items: center; gap: 7px; margin-top: 8px; font-size: 12px; }
.caudal :deep(.caudal-input) { width: 62px; }

/* Barras de costo */
.bar-item + .bar-item { margin-top: 12px; }
.bar-head { display: flex; justify-content: space-between; font-size: 13.5px; margin-bottom: 5px; }
.bar { height: 8px; background: #eef1ea; border-radius: 6px; overflow: hidden; }
.bar span { display: block; height: 100%; background: var(--leaf); border-radius: 6px; }

/* Mapa y galerías */
.inc-map { height: 380px; border-radius: 12px; overflow: hidden; }
.map-note { margin: 8px 0 0; line-height: 1.5; }
.obs-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 12px; }
.obs-card { border: 1px solid var(--border); border-radius: 12px; overflow: hidden; background: var(--surface); }
.obs-img { width: 100%; height: 150px; object-fit: cover; display: block; }
.obs-body { padding: 12px; }
.obs-note { font-weight: 600; }
.obs-sev-row { display: flex; align-items: center; justify-content: space-between; margin-top: 8px; gap: 8px; }
.obs-diag { margin: 10px 0 0; font-size: 13.5px; }
.obs-reco { margin: 6px 0 0; font-size: 13px; color: #374151; }
.gal-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(155px, 1fr)); gap: 12px; }
.gal { margin: 0; border: 1px solid var(--border); border-radius: 12px; overflow: hidden; background: var(--surface); }
.gal img { width: 100%; height: 130px; object-fit: cover; display: block; }
.gal figcaption { padding: 8px 10px; font-size: 12.5px; }

:deep(.row-current) { background: #f2f7f2; }
</style>
