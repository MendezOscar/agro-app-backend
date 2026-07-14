<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  cyclesApi, inputsApi, tasksApi,
  type Cycle, type Cost, type CycleReport, type Phenology, type Input, type WorkTask,
} from '../api/resources'

const stageLabels = ['Planificación', 'Prep. suelo', 'Siembra', 'Manejo', 'Monitoreo', 'Cosecha', 'Poscosecha', 'Evaluación']
const stageStatus = ['Pendiente', 'En progreso', 'Completada']
const cycleStatus = ['Planificada', 'Activa', 'Cosechada', 'Cerrada']
const costKind = ['Mano de obra', 'Insumo', 'Maquinaria', 'Otro']
const phenoStages = ['Germinación', 'Vegetativo', 'Floración', 'Cuajado', 'Maduración', 'Senescencia']

const route = useRoute()
const router = useRouter()
const id = route.params.id as string

const cycle = ref<Cycle | null>(null)
const report = ref<CycleReport | null>(null)
const inputs = ref<Input[]>([])
const costs = ref<Cost[]>([])
const phenology = ref<Phenology[]>([])
const tasksByStage = ref<Record<string, WorkTask[]>>({})
const expanded = ref<string | null>(null)

const closed = () => cycle.value?.status === 3

// Formularios (uno a la vez: solo hay una etapa expandida).
const taskTitle = ref('')
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
}

async function toggle(stageId: string) {
  expanded.value = expanded.value === stageId ? null : stageId
  if (expanded.value && !tasksByStage.value[stageId]) {
    tasksByStage.value[stageId] = await tasksApi.byStage(stageId)
  }
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
  if (!taskTitle.value.trim()) return
  await tasksApi.create(stageId, { title: taskTitle.value.trim() })
  taskTitle.value = ''
  tasksByStage.value[stageId] = await tasksApi.byStage(stageId)
}
async function toggleTask(t: WorkTask) {
  await tasksApi.setStatus(t.id, t.status === 2 ? 0 : 2)
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
      <p class="muted" style="margin-top:-6px">Haz clic en una etapa para gestionar sus tareas, costos y datos. Avanza el estado a medida que trabajas.</p>

      <div v-for="s in cycle.stages" :key="s.id" style="border:1px solid #e5e7eb;border-radius:8px;margin-bottom:8px">
        <div style="display:flex;align-items:center;gap:12px;padding:10px 12px;cursor:pointer" @click="toggle(s.id)">
          <span style="flex:1"><strong>{{ stageLabels[s.kind] }}</strong></span>
          <span class="muted" v-if="stageSubtotal(s.id) > 0">{{ stageSubtotal(s.id).toFixed(2) }}</span>
          <select :value="s.status" @click.stop @change="setStageStatus(s.id, +($event.target as HTMLSelectElement).value)"
            :disabled="closed()" style="padding:6px">
            <option v-for="(l, idx) in stageStatus" :key="idx" :value="idx">{{ l }}</option>
          </select>
          <span>{{ expanded === s.id ? '▲' : '▼' }}</span>
        </div>

        <div v-if="expanded === s.id" style="padding:12px;border-top:1px solid #e5e7eb">
          <!-- Tareas -->
          <h4>Tareas</h4>
          <div v-for="t in tasksByStage[s.id] || []" :key="t.id" style="display:flex;align-items:center;gap:8px;margin:4px 0">
            <input type="checkbox" :checked="t.status === 2" :disabled="closed()" @change="toggleTask(t)" />
            <span :style="{ textDecoration: t.status === 2 ? 'line-through' : 'none', flex: 1 }">{{ t.title }}</span>
            <a href="#" style="color:#dc2626;font-size:0.85em" @click.prevent="removeTask(t)">Eliminar</a>
          </div>
          <div v-if="!(tasksByStage[s.id] || []).length" class="muted">Sin tareas.</div>
          <div v-if="!closed()" style="margin-top:6px">
            <input v-model="taskTitle" placeholder="Nueva tarea" style="padding:6px" @keyup.enter="addTask(s.id)" />
            <button @click="addTask(s.id)" style="margin-left:6px;padding:6px 12px">Agregar</button>
          </div>

          <!-- Análisis de suelo (Planificación / Prep. suelo) -->
          <div v-if="s.kind === 0 || s.kind === 1" style="margin-top:12px">
            <a href="#" @click.prevent="router.push({ name: 'analyses', params: { id: cycle.plotId }, query: { name: report?.plotName ?? 'Lote' } })">
              → Análisis de suelo/agua del lote
            </a>
          </div>

          <!-- Monitoreo fenológico (etapa 5) -->
          <div v-if="s.kind === 4" style="margin-top:12px">
            <h4>Monitoreo fenológico</h4>
            <div class="row" style="align-items:flex-end;gap:8px;flex-wrap:wrap" v-if="!closed()">
              <label>Fecha <input v-model="phenoForm.recordedAt" type="date" style="padding:6px" /></label>
              <label>Etapa
                <select v-model.number="phenoForm.stage" style="padding:6px">
                  <option v-for="(l, idx) in phenoStages" :key="idx" :value="idx">{{ l }}</option>
                </select>
              </label>
              <label>Altura (cm) <input v-model.number="phenoForm.plantHeightCm" type="number" step="0.1" style="padding:6px;width:80px" /></label>
              <label>Plagas (%) <input v-model.number="phenoForm.pestIncidencePct" type="number" step="0.1" style="padding:6px;width:80px" /></label>
              <label>Enferm. (%) <input v-model.number="phenoForm.diseaseIncidencePct" type="number" step="0.1" style="padding:6px;width:80px" /></label>
              <label>Notas <input v-model="phenoForm.notes" style="padding:6px" /></label>
              <button @click="addPhenology" style="padding:8px 14px;background:#16a34a;color:#fff;border:none;border-radius:6px;cursor:pointer">Registrar</button>
            </div>
            <table style="margin-top:8px">
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
          <h4 style="margin-top:12px">Costos de la etapa</h4>
          <div class="row" style="align-items:flex-end;gap:8px;flex-wrap:wrap" v-if="!closed()">
            <label>Tipo
              <select v-model.number="costForm.kind" style="padding:6px">
                <option v-for="(l, idx) in costKind" :key="idx" :value="idx">{{ l }}</option>
              </select>
            </label>
            <label>Insumo
              <select v-model="costForm.inputId" style="padding:6px">
                <option value="">— manual —</option>
                <option v-for="i in inputs" :key="i.id" :value="i.id">{{ i.name }} ({{ i.unit }})</option>
              </select>
            </label>
            <label>Cantidad <input v-model.number="costForm.quantity" type="number" step="0.01" style="padding:6px;width:80px" /></label>
            <label v-if="!costForm.inputId">Costo unit. <input v-model.number="costForm.unitCost" type="number" step="0.01" style="padding:6px;width:90px" /></label>
            <label v-else class="muted">Unit.: {{ (selectedInput()?.unitCost ?? 0).toFixed(2) }}</label>
            <label>Descripción <input v-model="costForm.description" style="padding:6px" /></label>
            <button @click="addCost(s.id)" style="padding:8px 14px;background:#16a34a;color:#fff;border:none;border-radius:6px;cursor:pointer">Agregar</button>
          </div>
          <table style="margin-top:8px">
            <tbody>
              <tr v-for="c in costsForStage(s.id)" :key="c.id">
                <td>{{ costKind[c.kind] }}</td><td>{{ inputName(c.inputId) }}</td>
                <td class="muted">{{ c.description }}</td><td>{{ c.quantity }}</td><td>{{ c.total.toFixed(2) }}</td>
                <td><a href="#" style="color:#dc2626" @click.prevent="removeCost(c.id)">Eliminar</a></td>
              </tr>
              <tr v-if="!costsForStage(s.id).length"><td colspan="6" class="muted">Sin costos en esta etapa.</td></tr>
            </tbody>
          </table>

          <!-- Cierre de cosecha (Evaluación) -->
          <div v-if="s.kind === 7 && !closed()" style="margin-top:12px">
            <h4>Cerrar cosecha</h4>
            <div class="row" style="flex-wrap:wrap;gap:8px">
              <label>Rendimiento (kg) <input v-model.number="closeForm.yieldKg" type="number" style="padding:6px" /></label>
              <label>Pérdida poscosecha (kg) <input v-model.number="closeForm.postHarvestLossKg" type="number" style="padding:6px" /></label>
              <label>Ingreso estimado <input v-model.number="closeForm.revenueEst" type="number" style="padding:6px" /></label>
              <label>Calidad <input v-model="closeForm.quality" style="padding:6px" /></label>
            </div>
            <textarea v-model="closeForm.notes" placeholder="Notas" style="width:100%;margin-top:8px"></textarea>
            <button @click="closeCycle" style="margin-top:8px;padding:10px 16px;background:#16a34a;color:#fff;border:none;border-radius:8px;cursor:pointer">Cerrar ciclo</button>
          </div>
          <div v-if="s.kind === 7 && closed()" class="muted" style="margin-top:12px">Ciclo cerrado. Rendimiento: {{ cycle.yieldKg }} kg.</div>
        </div>
      </div>
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
