<script setup lang="ts">
import { onMounted, nextTick, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import maplibregl from 'maplibre-gl'
import {
  cyclesApi, farmsApi, harvestApi, inputsApi, tasksApi, usersApi,
  type Cycle, type Cost, type CycleReport, type Phenology, type Input, type WorkTask, type OrgUser, type Observation,
  type AgronomyResult, type PlotPhoto, type PlotProfitability, type FertilizationPlan, type Plot, type HarvestStepsResponse,
} from '../api/resources'
import { confirmDialog, alertDialog } from '../composables/dialog'
import { computeAgronomy } from '../composables/agronomy'

const stageLabels = ['Planificación', 'Prep. suelo', 'Siembra', 'Manejo', 'Monitoreo', 'Cosecha', 'Poscosecha', 'Evaluación']
const stageStatus = ['Pendiente', 'En progreso', 'Completada']
const cycleStatus = ['Planificada', 'Activa', 'Cosechada', 'Cerrada']
const costKind = ['Mano de obra', 'Insumo', 'Maquinaria', 'Otro']
const phenoStages = ['Germinación', 'Vegetativo', 'Floración', 'Cuajado', 'Maduración', 'Senescencia']
const taskStatusLabels = ['Por hacer', 'En progreso', 'Hecho']

const route = useRoute()
const router = useRouter()
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
const team = ref<OrgUser[]>([])
const expanded = ref<string | null>(null)

const closed = () => cycle.value?.status === 3

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
    ['Costo total', r.totalCost.toFixed(2)],
    ['Ingreso estimado', r.revenueEst.toFixed(2)],
    ['Margen', r.margin.toFixed(2)],
    ['Costo por kg', r.costPerKg.toFixed(2)],
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
  const kindRows = r.costByKind.map((c) => row(costKind[c.kind], c.total.toFixed(2))).join('')
  const stageRows = r.costByStage.map((c) => row(c.kind === null ? 'Sin etapa' : stageLabels[c.kind], c.total.toFixed(2))).join('')
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
      <div><span class="muted">Rendimiento</span><span><strong>${r.yieldKg.toFixed(0)} kg</strong> (${r.yieldPerHa.toFixed(1)} kg/ha)</span></div>
      <div><span class="muted">Costo total</span><strong>${r.totalCost.toFixed(2)}</strong></div>
      <div><span class="muted">Ingreso estimado</span><strong>${r.revenueEst.toFixed(2)}</strong></div>
      <div><span class="muted">Margen</span><strong>${r.margin.toFixed(2)}</strong></div>
      <div><span class="muted">Costo por kg</span><strong>${r.costPerKg.toFixed(2)}</strong></div>
      <div><span class="muted">Pérdida poscosecha</span><strong>${r.postHarvestLossKg.toFixed(0)} kg (${r.lossPct.toFixed(1)}%)</strong></div>
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
    '📋 *Reporte AgroApp*',
    `🌱 ${r.crop}${r.variety ? ' · ' + r.variety : ''}`,
    `📍 Lote: ${r.plotName ?? '—'} (${r.areaHa.toFixed(2)} ha)`,
    `Estado: ${cycleStatus[r.status]}`,
    `Rendimiento: ${r.yieldKg.toFixed(0)} kg (${r.yieldPerHa.toFixed(1)} kg/ha)`,
    `Costo total: ${r.totalCost.toFixed(2)}`,
    `Ingreso estimado: ${r.revenueEst.toFixed(2)}`,
    `Margen: ${r.margin.toFixed(2)}`,
    `Costo por kg: ${r.costPerKg.toFixed(2)}`,
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
  initIncidentMap()
  loadAgronomy()
  // Selecciona la etapa actual (en progreso; si no, la primera sin completar).
  const stages = cycle.value?.stages ?? []
  if (!expanded.value && stages.length) {
    const current = stages.find((s) => s.status === 1) ?? stages.find((s) => s.status !== 2) ?? stages[0]
    await selectStage(current.id)
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
  const stage = cycle.value?.stages?.find((s) => s.id === stageId)
  if (stage?.kind === 5 && !harvest.value) loadHarvest()
}

// Pasos de cosecha (etapa 5), configurables por cliente/cultivo.
const harvest = ref<HarvestStepsResponse | null>(null)
async function loadHarvest() {
  try { harvest.value = await harvestApi.steps(id) } catch { harvest.value = null }
}
async function saveHarvestStep(step: HarvestStepsResponse['steps'][number]) {
  const r = await harvestApi.updateStep(step.id, {
    status: step.status, qtyIn: step.qtyIn, qtyOut: step.qtyOut, notes: step.notes,
  })
  Object.assign(step, r)
  if (harvest.value) harvest.value.done = harvest.value.steps.filter((s) => s.status === 2).length
}
const merma = (s: HarvestStepsResponse['steps'][number]) =>
  s.qtyIn != null && s.qtyOut != null ? s.qtyIn - s.qtyOut : null
const harvestStatusColor = (st: number) => ['#94a3b8', '#f59e0b', '#16a34a'][st]
const stageStatusColor = (status: number) => ['#94a3b8', '#f59e0b', '#16a34a'][status]

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
  return costsForStage(stageId).reduce((s, c) => s + c.total, 0)
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
const unassignedCosts = () => costs.value.filter((c) => !c.stageId)

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
  await cyclesApi.close(id, closeForm.value)
  await load()
}
</script>

<template>
  <div v-if="cycle">
    <a href="#" @click.prevent="router.back()">← Volver</a>
    <h2>{{ cycle.crop }} <span class="muted">· {{ cycleStatus[cycle.status] }}</span></h2>

    <!-- Reporte consolidado -->
    <div class="card" v-if="report">
      <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">
        <h3 style="margin:0;flex:1">Reporte consolidado</h3>
        <button class="btn-ghost" style="padding:6px 12px" @click="downloadCsv">⬇ CSV</button>
        <button class="btn-ghost" style="padding:6px 12px" @click="printReport">🖨 PDF</button>
        <button class="btn-ghost" style="padding:6px 12px" @click="shareWhatsApp">🟢 WhatsApp</button>
      </div>
      <div class="row" style="flex-wrap:wrap;gap:16px">
        <div><div class="muted">Rendimiento</div><strong>{{ report.yieldKg.toFixed(0) }} kg</strong> <span class="muted">({{ report.yieldPerHa.toFixed(1) }} kg/ha)</span></div>
        <div><div class="muted">Costo total</div><strong>{{ report.totalCost.toFixed(2) }}</strong></div>
        <div><div class="muted">Ingreso estimado</div><strong>{{ report.revenueEst.toFixed(2) }}</strong></div>
        <div><div class="muted">Margen</div><strong :style="{ color: report.margin >= 0 ? '#16a34a' : '#dc2626' }">{{ report.margin.toFixed(2) }}</strong></div>
        <div><div class="muted">Costo por kg</div><strong>{{ report.costPerKg.toFixed(2) }}</strong></div>
        <div><div class="muted">Lote / área</div><strong>{{ report.plotName ?? '—' }}</strong> <span class="muted">{{ report.areaHa.toFixed(2) }} ha</span></div>
      </div>
      <div v-if="report.costByStage.length" style="margin-top:10px">
        <div class="muted">Costo por etapa</div>
        <span v-for="(cs, i) in report.costByStage" :key="i" style="display:inline-block;margin:3px;padding:2px 8px;background:#f1f5f9;border-radius:6px">
          {{ cs.kind === null ? 'Sin etapa' : stageLabels[cs.kind] }}: <strong>{{ cs.total.toFixed(2) }}</strong>
        </span>
      </div>
    </div>

    <!-- Agronomía (Open-Meteo): suelo, riego, GDD, riesgo -->
    <div class="card" style="margin-top:16px" v-if="agronomy">
      <div style="display:flex;align-items:center;gap:10px">
        <h3 style="margin:0;flex:1">Agronomía <span class="muted">· clima del cultivo</span></h3>
        <button class="btn-ghost" style="padding:6px 12px" @click="loadAgronomy">↻</button>
      </div>
      <p v-if="agronomy.message" class="muted" style="margin:8px 0 0">{{ agronomy.message }}</p>
      <div v-else class="agro-grid">
        <!-- Suelo por profundidad -->
        <div class="agro-box" v-if="agronomy.soil.length">
          <div class="agro-title">Suelo por profundidad</div>
          <div class="agro-valid">Lectura actual (hora)</div>
          <table class="agro-soil">
            <thead><tr><th>Prof.</th><th>Temp.</th><th>Humedad</th></tr></thead>
            <tbody>
              <tr v-for="l in agronomy.soil" :key="l.depthLabel">
                <td>{{ l.depthLabel }}</td>
                <td>{{ l.tempC != null ? l.tempC.toFixed(1) + ' °C' : '—' }}</td>
                <td>{{ l.moisturePct != null ? l.moisturePct.toFixed(0) + ' %' : '—' }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <!-- Balance hídrico / riego -->
        <div class="agro-box" v-if="agronomy.water">
          <div class="agro-title">Riego (balance hídrico)</div>
          <div class="agro-valid">Últimos 7 días + 7 de pronóstico</div>
          <div v-if="agronomy.water.kc">Kc <strong>{{ agronomy.water.kc.toFixed(2) }}</strong> <span class="muted">({{ agronomy.water.kcStage }})</span> · ETc <strong>{{ agronomy.water.etcMm7d?.toFixed(1) }} mm</strong></div>
          <div>ET0: <strong>{{ agronomy.water.et0Mm7d.toFixed(1) }} mm</strong> · Lluvia: <strong>{{ agronomy.water.precipMm7d.toFixed(1) }} mm</strong></div>
          <div>Déficit: <strong>{{ agronomy.water.deficitMm.toFixed(1) }} mm</strong></div>
          <div class="agro-badge" :style="agronomy.water.irrigationSuggested ? 'background:#fef3c7;color:#b45309' : 'background:#dcfce7;color:#15803d'">
            {{ agronomy.water.irrigationSuggested ? `Riego recomendado ~${agronomy.water.suggestedMm.toFixed(0)} mm` : 'Sin déficit relevante' }}
          </div>
          <div v-if="agronomy.water.irrigationSuggested && agronomy.water.volumeM3" style="margin-top:6px">
            Volumen: <strong>{{ agronomy.water.volumeM3.toLocaleString('es') }} m³</strong>
            <span v-if="caudal > 0"> · ~<strong>{{ (agronomy.water.volumeM3 / caudal).toFixed(1) }} h</strong></span>
          </div>
          <div v-if="agronomy.water.irrigationSuggested" class="muted" style="display:flex;align-items:center;gap:6px;margin-top:4px;font-size:12px">
            Caudal
            <input type="number" min="1" :value="caudal" @input="setCaudal(Number(($event.target as HTMLInputElement).value))"
              style="width:64px;padding:2px 6px;border:1px solid var(--border);border-radius:6px" /> m³/h
          </div>
        </div>
        <!-- GDD -->
        <div class="agro-box" v-if="agronomy.gdd && agronomy.gdd.days > 0">
          <div class="agro-title">Grados-día (GDD)</div>
          <div class="agro-valid">Desde el inicio del ciclo</div>
          <div class="agro-big">{{ agronomy.gdd.accumulated.toFixed(0) }} <span class="muted" style="font-size:13px">°C·día</span></div>
          <div class="muted">Base {{ agronomy.gdd.baseTempC }} °C · {{ agronomy.gdd.days }} días acumulados</div>
        </div>
        <!-- Riesgo de enfermedad -->
        <div class="agro-box" v-if="agronomy.disease">
          <div class="agro-title">Riesgo de enfermedad</div>
          <div class="agro-valid">Últimas 48 h</div>
          <span class="agro-badge" :style="{ background: sevColors[agronomy.disease.level] + '22', color: sevColors[agronomy.disease.level] }">
            {{ diseaseLabels[agronomy.disease.level] || agronomy.disease.level }}
          </span>
          <div class="muted" style="margin-top:6px;font-size:12px">{{ agronomy.disease.reason }}</div>
        </div>
      </div>
      <div class="muted" style="margin-top:8px;font-size:11px">Datos: Open-Meteo · se recalcula al abrir el ciclo o con ↻</div>
    </div>

    <!-- Mapa del lote: incidentes geolocalizados -->
    <div class="card" style="margin-top:16px" v-if="mapToken && (plot?.boundary || geoObs().length)">
      <h3>Mapa del lote <span class="muted">· {{ geoObs().length }} incidente(s) geolocalizado(s)</span></h3>
      <div class="inc-map-wrap">
        <div ref="mapEl" class="inc-map"></div>
        <!-- Semáforo del lote + viento/deriva -->
        <div class="map-hud" v-if="agronomy || wind">
          <div class="hud-row" v-if="agronomy">
            <span class="hud-dot" :style="{ background: plotRisk().color }"></span>
            <span>Estado del lote: <strong>{{ plotRisk().label }}</strong></span>
          </div>
          <div class="hud-row" v-if="wind">
            <span class="hud-arrow" :style="{ transform: `rotate(${wind.dir + 180}deg)` }">↑</span>
            <span>Viento <strong>{{ Math.round(wind.speed) }} km/h</strong><span v-if="wind.gust > wind.speed + 3" class="muted"> · ráfagas {{ Math.round(wind.gust) }}</span></span>
          </div>
          <div class="hud-row" v-if="drift()">
            <span class="hud-dot" :style="{ background: drift()!.color }"></span>
            <span>Aspersión: <strong :style="{ color: drift()!.color }">{{ drift()!.label }}</strong></span>
          </div>
        </div>
      </div>
      <div class="muted" style="margin-top:6px;font-size:12px">Pines = observaciones (color por severidad IA). El contorno del lote colorea su estado agronómico; el recuadro muestra viento y aptitud para aspersión.</div>
    </div>

    <!-- Rentabilidad del lote / comparación de temporadas -->
    <div class="card" style="margin-top:16px" v-if="profit && profit.cycles.length">
      <h3>Rentabilidad del lote <span class="muted">· {{ profit.plotName ?? '' }} ({{ profit.areaHa.toFixed(2) }} ha)</span></h3>
      <div class="row" style="flex-wrap:wrap;gap:16px;margin-bottom:6px">
        <div><div class="muted">Temporadas</div><strong>{{ profit.seasons }}</strong></div>
        <div><div class="muted">Margen acumulado</div><strong :style="{ color: profit.totalMargin >= 0 ? '#16a34a' : '#dc2626' }">{{ profit.totalMargin.toFixed(2) }}</strong></div>
        <div><div class="muted">Rend. promedio</div><strong>{{ profit.avgYieldPerHa.toFixed(1) }} kg/ha</strong></div>
        <div><div class="muted">Costo promedio</div><strong>{{ profit.avgCostPerKg.toFixed(2) }} /kg</strong></div>
      </div>
      <div style="overflow-x:auto">
        <table style="margin-top:6px">
          <thead><tr><th>Temporada</th><th>Estado</th><th>Rend. (kg)</th><th>kg/ha</th><th>Costo</th><th>Ingreso</th><th>Margen</th><th>$/kg</th></tr></thead>
          <tbody>
            <tr v-for="s in profit.cycles" :key="s.cycleId" :style="s.cycleId === id ? 'background:#f1f7f1' : ''">
              <td>{{ s.crop }}<span v-if="s.variety" class="muted"> · {{ s.variety }}</span><div class="muted" style="font-size:12px">{{ s.start ?? '—' }}</div></td>
              <td>{{ cycleStatus[s.status] }}</td>
              <td>{{ s.yieldKg.toFixed(0) }}</td>
              <td>{{ s.yieldPerHa.toFixed(1) }}</td>
              <td>{{ s.totalCost.toFixed(2) }}</td>
              <td>{{ s.revenueEst.toFixed(2) }}</td>
              <td :style="{ color: s.margin >= 0 ? '#16a34a' : '#dc2626', fontWeight: 600 }">{{ s.margin.toFixed(2) }}</td>
              <td>{{ s.costPerKg.toFixed(2) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Plan de fertilización (desde análisis de suelo) -->
    <div class="card" style="margin-top:16px" v-if="fert && fert.hasAnalysis">
      <h3>Plan de fertilización <span class="muted">· suelo{{ fert.sampledAt ? ' · muestra ' + fert.sampledAt : '' }}</span></h3>
      <div style="overflow-x:auto">
        <table style="margin-top:6px">
          <thead><tr><th>Nutriente</th><th>Valor</th><th>Estado</th><th>Recomendación</th></tr></thead>
          <tbody>
            <tr v-for="it in fert.items" :key="it.nutrient">
              <td><strong>{{ it.nutrient }}</strong></td>
              <td>{{ it.value != null ? it.value + (it.unit ? ' ' + it.unit : '') : '—' }}</td>
              <td><span class="agro-badge" :style="{ background: fertColors[it.status] + '22', color: fertColors[it.status] }">{{ fertLabels[it.status] || it.status }}</span></td>
              <td style="font-size:13px">{{ it.recommendation }}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Receta / dosis por objetivo de rendimiento -->
      <template v-if="fert.recipe && fert.recipe.doses.length">
        <h4 class="section-title" style="margin-top:16px">Receta orientativa
          <span class="muted" style="font-weight:400">· {{ fert.recipe.crop }} · meta {{ fert.recipe.targetYieldTonHa }} t/ha · {{ fert.recipe.areaHa.toFixed(2) }} ha</span>
        </h4>
        <div style="overflow-x:auto">
          <table style="margin-top:6px">
            <thead><tr><th>Nutriente</th><th>Dosis</th><th>Producto</th><th>Cantidad lote</th><th>Bultos</th><th>Costo est.</th></tr></thead>
            <tbody>
              <tr v-for="d in fert.recipe.doses" :key="d.nutrient">
                <td><strong>{{ d.nutrient }}</strong></td>
                <td>{{ d.doseKgHa }} kg/ha</td>
                <td>{{ d.product }}<div class="muted" style="font-size:12px">{{ d.productKgHa }} kg/ha</div></td>
                <td>{{ d.totalKg.toLocaleString('es') }} kg</td>
                <td>{{ d.bags }}</td>
                <td>L {{ d.estCost.toLocaleString('es') }}</td>
              </tr>
              <tr style="font-weight:700;background:#f1f7f1">
                <td colspan="5" style="text-align:right">Total estimado</td>
                <td>L {{ fert.recipe.totalCost.toLocaleString('es') }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p class="muted" style="margin-top:8px;font-size:12px">{{ fert.recipe.note }}</p>
      </template>

      <p class="muted" style="margin-top:8px;font-size:12px">{{ fert.note }}</p>
    </div>

    <!-- Historial visual del lote -->
    <div class="card" style="margin-top:16px" v-if="plotPhotos.length">
      <h3>Historial visual del lote <span class="muted">· {{ plotPhotos.length }} foto(s)</span></h3>
      <p class="muted" style="margin-top:-6px">Evolución del lote a través de las observaciones con foto de todos sus ciclos.</p>
      <div class="gal-grid">
        <figure class="gal" v-for="p in plotPhotos" :key="p.id">
          <a :href="p.photoUrl" target="_blank" rel="noopener">
            <img :src="p.photoUrl" loading="lazy" />
          </a>
          <figcaption>
            <strong>{{ new Date(p.createdAt).toLocaleDateString('es', { day: '2-digit', month: 'short', year: '2-digit' }) }}</strong>
            · {{ p.crop }}
            <span v-if="p.analysis" class="gal-badge" :style="{ background: sevColors[p.analysis.severity] + '22', color: sevColors[p.analysis.severity] }">{{ sevLabels[p.analysis.severity] || p.analysis.severity }}</span>
            <div v-if="p.note" class="muted gal-note">{{ p.note }}</div>
          </figcaption>
        </figure>
      </div>
    </div>

    <!-- Etapas (acordeón) -->
    <div class="card" style="margin-top:16px">
      <h3>Etapas del ciclo</h3>
      <p class="muted" style="margin-top:-6px">Selecciona una etapa para gestionar sus tareas, costos y datos. Avanza el estado a medida que trabajas.</p>

      <!-- Stepper horizontal de etapas -->
      <div style="display:flex;flex-wrap:wrap;gap:6px;margin:10px 0 16px">
        <button v-for="s in cycle.stages" :key="s.id" @click="selectStage(s.id)"
          :style="{
            display:'flex', alignItems:'center', gap:'6px', padding:'8px 12px', cursor:'pointer',
            borderRadius:'8px', fontSize:'0.9em', color:'#1a1a1a',
            border: expanded === s.id ? '2px solid #16a34a' : '1px solid #e5e7eb',
            background: expanded === s.id ? '#f0fdf4' : '#fff',
            fontWeight: expanded === s.id ? 700 : 400,
          }">
          <span :style="{ width:'9px', height:'9px', borderRadius:'50%', background: stageStatusColor(s.status) }"></span>
          {{ stageLabels[s.kind] }}
          <span v-if="stageSubtotal(s.id) > 0" class="muted" style="font-size:0.85em">· {{ stageSubtotal(s.id).toFixed(0) }}</span>
        </button>
      </div>

      <template v-for="s in cycle.stages" :key="s.id">
        <div v-if="expanded === s.id" style="border:1px solid #e5e7eb;border-radius:8px;padding:16px">
          <div style="display:flex;align-items:center;gap:12px;margin-bottom:12px">
            <h3 style="flex:1;margin:0">{{ stageLabels[s.kind] }}</h3>
            <span class="muted">Estado:</span>
            <select :value="s.status" @change="setStageStatus(s.id, +($event.target as HTMLSelectElement).value)"
              :disabled="closed()" style="padding:6px">
              <option v-for="(l, idx) in stageStatus" :key="idx" :value="idx">{{ l }}</option>
            </select>
          </div>
          <!-- Tareas -->
          <div class="section" style="margin-top:0;padding-top:0;border-top:none">
            <h4 class="section-title">Tareas</h4>
            <div v-for="t in tasksByStage[s.id] || []" :key="t.id" style="display:flex;align-items:flex-start;gap:10px;padding:8px 0;border-bottom:1px solid #f1f5f9">
              <input type="checkbox" :checked="t.status === 2" :disabled="closed()" @change="toggleTask(t)" style="margin-top:3px" />
              <div style="flex:1">
                <div :style="{ textDecoration: t.status === 2 ? 'line-through' : 'none', fontWeight: 600 }">{{ t.title }}</div>
                <div v-if="t.description" class="muted">{{ t.description }}</div>
                <div class="muted">
                  <span v-if="userName(t.assignedToUserId)">👤 {{ userName(t.assignedToUserId) }}</span>
                  <span v-if="t.dueDate"> · 📅 {{ t.dueDate }}</span>
                </div>
              </div>
              <select :value="t.status" :disabled="closed()"
                @change="setTaskStatus(t, +($event.target as HTMLSelectElement).value)">
                <option v-for="(l, idx) in taskStatusLabels" :key="idx" :value="idx">{{ l }}</option>
              </select>
              <a href="#" style="color:#dc2626;font-size:13px;margin-top:4px" @click.prevent="removeTask(t)">Eliminar</a>
            </div>
            <div v-if="!(tasksByStage[s.id] || []).length" class="muted" style="padding:6px 0">Sin tareas en esta etapa.</div>
            <div v-if="!closed()" class="form-box" style="margin-top:10px">
              <label>Título <input v-model="taskForm.title" placeholder="Ej. Arar el lote" @keyup.enter="addTask(s.id)" /></label>
              <label>Descripción <input v-model="taskForm.description" /></label>
              <label>Responsable
                <select v-model="taskForm.assignedToUserId">
                  <option value="">— sin asignar —</option>
                  <option v-for="u in team" :key="u.id" :value="u.id">{{ u.fullName }}</option>
                </select>
              </label>
              <label>Fecha límite <input v-model="taskForm.dueDate" type="date" /></label>
              <button class="btn btn-sm" @click="addTask(s.id)">Agregar tarea</button>
            </div>
          </div>

          <!-- Análisis de suelo (Planificación / Prep. suelo) -->
          <div v-if="s.kind === 0 || s.kind === 1" class="section">
            <h4 class="section-title">Análisis de suelo / agua</h4>
            <a href="#" @click.prevent="router.push({ name: 'analyses', params: { id: cycle.plotId }, query: { name: report?.plotName ?? 'Lote' } })">
              → Ver y registrar análisis del lote
            </a>
          </div>

          <!-- Monitoreo fenológico (etapa 5) -->
          <div v-if="s.kind === 4" class="section">
            <h4 class="section-title">Monitoreo fenológico</h4>
            <div class="form-box" v-if="!closed()">
              <label>Fecha <input v-model="phenoForm.recordedAt" type="date" /></label>
              <label>Etapa
                <select v-model.number="phenoForm.stage">
                  <option v-for="(l, idx) in phenoStages" :key="idx" :value="idx">{{ l }}</option>
                </select>
              </label>
              <label>Altura (cm) <input v-model.number="phenoForm.plantHeightCm" type="number" step="0.1" style="width:90px" /></label>
              <label>Plagas (%) <input v-model.number="phenoForm.pestIncidencePct" type="number" step="0.1" style="width:90px" /></label>
              <label>Enferm. (%) <input v-model.number="phenoForm.diseaseIncidencePct" type="number" step="0.1" style="width:90px" /></label>
              <label>Notas <input v-model="phenoForm.notes" /></label>
              <button class="btn btn-sm" @click="addPhenology">Registrar</button>
            </div>
            <table style="margin-top:10px">
              <thead><tr><th>Fecha</th><th>Etapa</th><th>Altura</th><th>Plagas%</th><th>Enf.%</th><th>Notas</th><th></th></tr></thead>
              <tbody>
                <tr v-for="r in phenology" :key="r.id">
                  <td>{{ r.recordedAt }}</td><td>{{ phenoStages[r.stage] }}</td><td>{{ r.plantHeightCm ?? '—' }}</td>
                  <td>{{ r.pestIncidencePct ?? '—' }}</td><td>{{ r.diseaseIncidencePct ?? '—' }}</td>
                  <td class="muted">{{ r.notes }}</td>
                  <td><a href="#" style="color:#dc2626" @click.prevent="removePhenology(r.id)">Eliminar</a></td>
                </tr>
                <tr v-if="!phenology.length"><td colspan="7" class="muted">Sin registros.</td></tr>
              </tbody>
            </table>

            <h4 class="section-title" style="margin-top:18px">Observaciones con análisis IA</h4>
            <div class="obs-grid">
              <div v-for="o in observations" :key="o.id" class="obs-card">
                <img v-if="o.photoUrl" :src="o.photoUrl" class="obs-img" />
                <div class="obs-body">
                  <div class="obs-note">{{ o.note || '(sin nota)' }}</div>
                  <div v-if="!o.analysis" class="muted" style="margin-top:6px">Análisis IA en proceso…</div>
                  <template v-else>
                    <div class="obs-sev-row">
                      <span class="obs-badge" :style="{ background: sevColors[o.analysis.severity] + '22', color: sevColors[o.analysis.severity] }">
                        Severidad: {{ sevLabels[o.analysis.severity] || '—' }}
                      </span>
                      <span class="muted">Confianza {{ Math.round((o.analysis.confidence ?? 0) * 100) }}%</span>
                    </div>
                    <div class="obs-diag">{{ diagText(o.analysis.diagnosis) }}</div>
                    <div v-if="o.analysis.recommendations" class="obs-reco">
                      <strong>Recomendaciones:</strong> {{ o.analysis.recommendations }}
                    </div>
                  </template>
                </div>
              </div>
              <div v-if="!observations.length" class="muted">Sin observaciones. Se registran desde la app (foto de la planta).</div>
            </div>
          </div>

          <!-- Proceso de cosecha por pasos (etapa 6 = Cosecha) -->
          <div v-if="s.kind === 5" class="section harvest">
            <h4 class="section-title">Proceso de cosecha
              <span class="muted" v-if="harvest">· {{ harvest.done }}/{{ harvest.total }} pasos</span>
              <a href="#" class="hv-cfg" @click.prevent="router.push({ name: 'harvest-templates', query: { crop: cycle.crop } })">⚙ configurar pasos</a>
            </h4>
            <div v-if="!harvest" class="muted">Cargando pasos…</div>
            <template v-else>
              <div class="hv-bar"><span :style="{ width: harvest.total ? (harvest.done / harvest.total * 100) + '%' : '0%' }"></span></div>
              <div class="hv-step" v-for="(st, i) in harvest.steps" :key="st.id">
                <div class="hv-head">
                  <span class="hv-dot" :style="{ background: harvestStatusColor(st.status) }">{{ st.status === 2 ? '✓' : i + 1 }}</span>
                  <strong>{{ st.name }}</strong>
                  <span style="flex:1"></span>
                  <select v-model.number="st.status" @change="saveHarvestStep(st)" :disabled="closed()">
                    <option :value="0">Pendiente</option><option :value="1">En progreso</option><option :value="2">Completado</option>
                  </select>
                </div>
                <div class="hv-fields" v-if="!closed()">
                  <label>Entra ({{ st.unit || 'kg' }}) <input v-model.number="st.qtyIn" type="number" step="0.1" @change="saveHarvestStep(st)" /></label>
                  <label>Sale ({{ st.unit || 'kg' }}) <input v-model.number="st.qtyOut" type="number" step="0.1" @change="saveHarvestStep(st)" /></label>
                  <span class="hv-merma" v-if="merma(st) != null">Merma: {{ merma(st)!.toFixed(1) }} {{ st.unit || 'kg' }}<span v-if="st.qtyIn"> ({{ (merma(st)! / st.qtyIn! * 100).toFixed(0) }}%)</span></span>
                  <label class="hv-notes">Notas <input v-model="st.notes" @change="saveHarvestStep(st)" /></label>
                </div>
                <div class="hv-fields" v-else>
                  <span class="muted">Entra {{ st.qtyIn ?? '—' }} · Sale {{ st.qtyOut ?? '—' }} {{ st.unit || 'kg' }}<span v-if="st.notes"> · {{ st.notes }}</span></span>
                </div>
              </div>
            </template>
          </div>

          <!-- Costos de la etapa -->
          <div class="section">
            <h4 class="section-title">Costos de la etapa <span class="muted" v-if="stageSubtotal(s.id) > 0">· subtotal {{ stageSubtotal(s.id).toFixed(2) }}</span></h4>
            <div class="form-box" v-if="!closed()">
              <label>Tipo
                <select v-model.number="costForm.kind">
                  <option v-for="(l, idx) in costKind" :key="idx" :value="idx">{{ l }}</option>
                </select>
              </label>
              <label>Insumo
                <select v-model="costForm.inputId">
                  <option value="">— manual —</option>
                  <option v-for="i in inputs" :key="i.id" :value="i.id">{{ i.name }} ({{ i.unit }})</option>
                </select>
              </label>
              <label>Cantidad <input v-model.number="costForm.quantity" type="number" step="0.01" style="width:90px" /></label>
              <label v-if="!costForm.inputId">Costo unit. <input v-model.number="costForm.unitCost" type="number" step="0.01" style="width:100px" /></label>
              <label v-else>Costo unit. (catálogo)<span style="padding:7px 0">{{ (selectedInput()?.unitCost ?? 0).toFixed(2) }}</span></label>
              <label>Descripción <input v-model="costForm.description" /></label>
              <button class="btn btn-sm" @click="addCost(s.id)">Agregar</button>
            </div>
            <table style="margin-top:10px">
              <thead><tr><th>Tipo</th><th>Insumo</th><th>Descripción</th><th>Cant.</th><th>Total</th><th></th></tr></thead>
              <tbody>
                <tr v-for="c in costsForStage(s.id)" :key="c.id">
                  <td>{{ costKind[c.kind] }}</td><td>{{ inputName(c.inputId) }}</td>
                  <td class="muted">{{ c.description }}</td><td>{{ c.quantity }}</td><td>{{ c.total.toFixed(2) }}</td>
                  <td><a href="#" style="color:#dc2626" @click.prevent="removeCost(c.id)">Eliminar</a></td>
                </tr>
                <tr v-if="!costsForStage(s.id).length"><td colspan="6" class="muted">Sin costos en esta etapa.</td></tr>
              </tbody>
            </table>
          </div>

          <!-- Cierre de cosecha (Evaluación) -->
          <div v-if="s.kind === 7" class="section">
            <h4 class="section-title">Cierre de cosecha</h4>
            <div v-if="!closed()">
              <div class="form-box">
                <label>Rendimiento (kg) <input v-model.number="closeForm.yieldKg" type="number" /></label>
                <label>Pérdida poscosecha (kg) <input v-model.number="closeForm.postHarvestLossKg" type="number" /></label>
                <label>Ingreso estimado <input v-model.number="closeForm.revenueEst" type="number" /></label>
                <label>Calidad <input v-model="closeForm.quality" /></label>
                <label style="flex:1;min-width:200px">Notas <input v-model="closeForm.notes" /></label>
              </div>
              <button class="btn" style="margin-top:10px" @click="closeCycle">Cerrar ciclo</button>
            </div>
            <div v-else class="muted">Ciclo cerrado. Rendimiento: {{ cycle.yieldKg }} kg.</div>
          </div>
        </div>
      </template>
    </div>

    <!-- Costos sin etapa (registrados antes del rediseño) -->
    <div class="card" style="margin-top:16px" v-if="unassignedCosts().length">
      <h3>Costos sin etapa</h3>
      <table>
        <tbody>
          <tr v-for="c in unassignedCosts()" :key="c.id">
            <td>{{ costKind[c.kind] }}</td><td class="muted">{{ c.description }}</td><td>{{ c.total.toFixed(2) }}</td>
            <td><a href="#" style="color:#dc2626" @click.prevent="removeCost(c.id)">Eliminar</a></td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<style scoped>
.harvest .hv-cfg { font-size: 12px; font-weight: 600; margin-left: 10px; }
.hv-bar { height: 8px; border-radius: 6px; background: #e5e7eb; overflow: hidden; margin: 8px 0 14px; }
.hv-bar span { display: block; height: 100%; background: var(--leaf); transition: width .3s ease; }
.hv-step { border: 1px solid var(--border); border-radius: 10px; padding: 10px 12px; margin-bottom: 8px; background: #fff; }
.hv-head { display: flex; align-items: center; gap: 9px; }
.hv-dot { width: 24px; height: 24px; border-radius: 50%; color: #fff; display: grid; place-items: center; font-size: 12px; font-weight: 700; flex-shrink: 0; }
.hv-head select { padding: 4px 8px; border: 1px solid var(--border); border-radius: 7px; }
.hv-fields { display: flex; flex-wrap: wrap; gap: 10px 14px; align-items: center; margin-top: 8px; padding-left: 33px; font-size: 14px; }
.hv-fields label { display: flex; align-items: center; gap: 6px; color: var(--muted); }
.hv-fields input { padding: 4px 8px; border: 1px solid var(--border); border-radius: 7px; width: 90px; }
.hv-fields .hv-notes { flex: 1; min-width: 160px; }
.hv-fields .hv-notes input { width: 100%; }
.hv-merma { color: var(--amber); font-weight: 600; }
.inc-map-wrap { position: relative; margin-top: 8px; }
.inc-map { height: 360px; border-radius: 10px; overflow: hidden; }
.map-hud { position: absolute; top: 10px; left: 10px; background: rgba(255,255,255,.94); border: 1px solid var(--border); border-radius: 10px; padding: 8px 12px; font-size: 12.5px; display: flex; flex-direction: column; gap: 5px; box-shadow: 0 2px 8px rgba(0,0,0,.12); }
.map-hud .hud-row { display: flex; align-items: center; gap: 7px; }
.map-hud .hud-dot { width: 11px; height: 11px; border-radius: 50%; flex-shrink: 0; }
.map-hud .hud-arrow { display: inline-block; font-weight: 800; color: var(--leaf-dark); transition: transform .3s ease; }
.obs-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 12px; margin-top: 10px; }
.obs-card { border: 1px solid #e5e7eb; border-radius: 10px; overflow: hidden; background: #fff; }
.obs-img { width: 100%; height: 150px; object-fit: cover; display: block; }
.obs-body { padding: 10px; }
.obs-note { font-weight: 600; }
.obs-sev-row { display: flex; align-items: center; justify-content: space-between; margin-top: 6px; }
.obs-badge { padding: 2px 8px; border-radius: 20px; font-size: 12px; font-weight: 600; }
.obs-diag { margin-top: 8px; font-size: 14px; }
.obs-reco { margin-top: 6px; font-size: 13px; color: #374151; }
.agro-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 12px; margin-top: 10px; }
.agro-box { border: 1px solid #e5e7eb; border-radius: 10px; padding: 10px; background: #fff; }
.agro-title { font-weight: 600; font-size: 13px; margin-bottom: 2px; }
.agro-valid { font-size: 11px; color: #9ca3af; margin-bottom: 6px; }
.agro-soil { width: 100%; font-size: 13px; }
.agro-soil th { text-align: left; color: #6b7280; font-weight: 500; }
.agro-big { font-size: 24px; font-weight: 700; }
.agro-badge { display: inline-block; margin-top: 6px; padding: 3px 10px; border-radius: 20px; font-size: 12px; font-weight: 600; }
.gal-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 12px; margin-top: 10px; }
.gal { margin: 0; border: 1px solid var(--border); border-radius: 12px; overflow: hidden; background: #fff; }
.gal img { width: 100%; height: 130px; object-fit: cover; display: block; }
.gal figcaption { padding: 8px 10px; font-size: 12.5px; }
.gal-badge { display: inline-block; padding: 1px 7px; border-radius: 12px; font-size: 11px; font-weight: 700; margin-left: 4px; }
.gal-note { font-size: 11.5px; margin-top: 3px; }
</style>
