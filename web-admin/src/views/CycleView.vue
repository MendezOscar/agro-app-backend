<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  cyclesApi, inputsApi, tasksApi, usersApi,
  type Cycle, type Cost, type CycleReport, type Phenology, type Input, type WorkTask, type OrgUser, type Observation,
  type AgronomyResult,
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
const diseaseLabels: Record<string, string> = { high: 'Alto', medium: 'Medio', low: 'Bajo', none: 'Sin riesgo' }
async function loadAgronomy() {
  try {
    const ctx = await cyclesApi.agronomyContext(id)
    agronomy.value = await computeAgronomy(ctx)
  } catch { agronomy.value = null }
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
}
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
          <div>ET0: <strong>{{ agronomy.water.et0Mm7d.toFixed(1) }} mm</strong> · Lluvia: <strong>{{ agronomy.water.precipMm7d.toFixed(1) }} mm</strong></div>
          <div>Déficit: <strong>{{ agronomy.water.deficitMm.toFixed(1) }} mm</strong></div>
          <div class="agro-badge" :style="agronomy.water.irrigationSuggested ? 'background:#fef3c7;color:#b45309' : 'background:#dcfce7;color:#15803d'">
            {{ agronomy.water.irrigationSuggested ? `Riego recomendado ~${agronomy.water.suggestedMm.toFixed(0)} mm` : 'Sin déficit relevante' }}
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
</style>
