<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  cyclesApi, inputsApi, tasksApi, usersApi,
  type Cycle, type Cost, type CycleReport, type Phenology, type Input, type WorkTask, type OrgUser,
} from '../api/resources'

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
const tasksByStage = ref<Record<string, WorkTask[]>>({})
const team = ref<OrgUser[]>([])
const expanded = ref<string | null>(null)

const closed = () => cycle.value?.status === 3

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
  try { team.value = await usersApi.list() } catch { team.value = [] }
  // Selecciona la primera etapa por defecto para mostrar su panel.
  if (!expanded.value && cycle.value?.stages?.length) await selectStage(cycle.value.stages[0].id)
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
  if (!confirm('¿Eliminar este costo?')) return
  await cyclesApi.removeCost(costId)
  await refreshCosts()
}
function inputName(inputId: string | null) {
  return inputId ? (inputs.value.find((i) => i.id === inputId)?.name ?? '—') : '—'
}
const unassignedCosts = () => costs.value.filter((c) => !c.stageId)

// --- Monitoreo fenológico (etapa 5) ---
async function addPhenology() {
  if (!phenoForm.value.recordedAt) { alert('Indica la fecha del registro.'); return }
  await cyclesApi.addPhenology(id, {
    recordedAt: phenoForm.value.recordedAt, stage: phenoForm.value.stage,
    plantHeightCm: phenoForm.value.plantHeightCm, pestIncidencePct: phenoForm.value.pestIncidencePct,
    diseaseIncidencePct: phenoForm.value.diseaseIncidencePct, notes: phenoForm.value.notes || null,
  })
  phenoForm.value = { recordedAt: '', stage: 0, plantHeightCm: null, pestIncidencePct: null, diseaseIncidencePct: null, notes: '' }
  phenology.value = await cyclesApi.phenology(id)
}
async function removePhenology(recId: string) {
  if (!confirm('¿Eliminar este registro?')) return
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
      <h3>Reporte consolidado</h3>
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
