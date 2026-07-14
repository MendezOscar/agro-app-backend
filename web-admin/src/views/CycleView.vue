<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { cyclesApi, inputsApi, type Cycle, type CostSummary, type Cost, type CycleReport, type Phenology, type Input } from '../api/resources'

const stageLabels = ['Planificación', 'Prep. suelo', 'Siembra', 'Manejo', 'Monitoreo', 'Cosecha', 'Poscosecha', 'Evaluación']
const stageStatus = ['Pendiente', 'En progreso', 'Completada']
const cycleStatus = ['Planificada', 'Activa', 'Cosechada', 'Cerrada']
const costKind = ['Mano de obra', 'Insumo', 'Maquinaria', 'Otro']

const route = useRoute()
const id = route.params.id as string
const cycle = ref<Cycle | null>(null)
const summary = ref<CostSummary | null>(null)
const costs = ref<Cost[]>([])
const inputs = ref<Input[]>([])
const report = ref<CycleReport | null>(null)
const phenoStages = ['Germinación', 'Vegetativo', 'Floración', 'Cuajado', 'Maduración', 'Senescencia']
const phenology = ref<Phenology[]>([])
const phenoForm = ref({ recordedAt: '', stage: 0, plantHeightCm: null as number | null, pestIncidencePct: null as number | null, diseaseIncidencePct: null as number | null, notes: '' })

const costForm = ref({ kind: 1, inputId: '', description: '', quantity: 1, unitCost: 0 })
const closeForm = ref({ yieldKg: 0, quality: '', postHarvestLossKg: 0, revenueEst: 0, notes: '' })

// Costo estimado: si hay insumo, usa su costo del catálogo; si no, el manual.
const selectedInput = computed(() => inputs.value.find((i) => i.id === costForm.value.inputId))
const estimatedTotal = computed(() => {
  const unit = costForm.value.inputId ? (selectedInput.value?.unitCost ?? 0) : costForm.value.unitCost
  return costForm.value.quantity * unit
})

onMounted(load)
async function load() {
  cycle.value = await cyclesApi.get(id)
  summary.value = await cyclesApi.costSummary(id)
  costs.value = await cyclesApi.costs(id)
  inputs.value = await inputsApi.list()
  report.value = await cyclesApi.report(id)
  // Tolerante: si la tabla aún no está migrada, no rompe el resto de la vista.
  try { phenology.value = await cyclesApi.phenology(id) } catch { phenology.value = [] }
}

async function addPhenology() {
  if (!phenoForm.value.recordedAt) { alert('Indica la fecha del registro.'); return }
  await cyclesApi.addPhenology(id, {
    recordedAt: phenoForm.value.recordedAt,
    stage: phenoForm.value.stage,
    plantHeightCm: phenoForm.value.plantHeightCm,
    pestIncidencePct: phenoForm.value.pestIncidencePct,
    diseaseIncidencePct: phenoForm.value.diseaseIncidencePct,
    notes: phenoForm.value.notes || null,
  })
  phenoForm.value = { recordedAt: '', stage: 0, plantHeightCm: null, pestIncidencePct: null, diseaseIncidencePct: null, notes: '' }
  phenology.value = await cyclesApi.phenology(id)
}

async function removePhenology(recId: string) {
  if (!confirm('¿Eliminar este registro?')) return
  await cyclesApi.removePhenology(recId)
  phenology.value = await cyclesApi.phenology(id)
}

async function addCost() {
  await cyclesApi.addCost(id, {
    kind: costForm.value.kind,
    description: costForm.value.description || null,
    inputId: costForm.value.inputId || null,
    quantity: costForm.value.quantity,
    // Con insumo mandamos 0 para que el backend tome el costo del catálogo.
    unitCost: costForm.value.inputId ? 0 : costForm.value.unitCost,
  })
  costForm.value = { kind: 1, inputId: '', description: '', quantity: 1, unitCost: 0 }
  await load()
}

async function removeCost(costId: string) {
  if (!confirm('¿Eliminar este costo?')) return
  await cyclesApi.removeCost(costId)
  await load()
}

function inputName(inputId: string | null) {
  return inputId ? (inputs.value.find((i) => i.id === inputId)?.name ?? '—') : '—'
}

async function setStageStatus(stageId: string, status: number) {
  await cyclesApi.advanceStage(stageId, { status })
  await load()
}

async function closeCycle() {
  await cyclesApi.close(id, closeForm.value)
  await load()
}
</script>

<template>
  <div v-if="cycle">
    <h2>{{ cycle.crop }} <span class="muted">· {{ cycleStatus[cycle.status] }}</span></h2>

    <div class="row">
      <div class="card" style="flex:2;min-width:360px">
        <h3>Etapas</h3>
        <p class="muted" style="margin-top:-6px">Avanza cada etapa a medida que trabajas: Pendiente → En progreso → Completada. Al iniciar la primera, el ciclo pasa a “Activa”.</p>
        <table>
          <tbody>
            <tr v-for="s in cycle.stages" :key="s.id">
              <td>{{ stageLabels[s.kind] }}</td>
              <td>
                <select :value="s.status" @change="setStageStatus(s.id, +($event.target as HTMLSelectElement).value)"
                  :disabled="cycle.status === 3" style="padding:6px">
                  <option v-for="(l, idx) in stageStatus" :key="idx" :value="idx">{{ l }}</option>
                </select>
              </td>
              <td class="muted">{{ s.notes }}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="card" style="flex:1;min-width:260px">
        <h3>Costos</h3>
        <div style="font-size:28px;font-weight:700">{{ summary?.total?.toFixed(2) ?? '0.00' }}</div>
        <table>
          <tbody>
            <tr v-for="k in summary?.byKind || []" :key="k.kind">
              <td>{{ costKind[k.kind] }}</td>
              <td style="text-align:right">{{ k.total.toFixed(2) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <div class="card" style="margin-top:16px" v-if="report">
      <h3>Reporte consolidado</h3>
      <div class="row" style="flex-wrap:wrap;gap:16px">
        <div><div class="muted">Rendimiento</div><strong>{{ report.yieldKg.toFixed(0) }} kg</strong> <span class="muted">({{ report.yieldPerHa.toFixed(1) }} kg/ha)</span></div>
        <div><div class="muted">Costo total</div><strong>{{ report.totalCost.toFixed(2) }}</strong></div>
        <div><div class="muted">Ingreso estimado</div><strong>{{ report.revenueEst.toFixed(2) }}</strong></div>
        <div>
          <div class="muted">Margen</div>
          <strong :style="{ color: report.margin >= 0 ? '#16a34a' : '#dc2626' }">{{ report.margin.toFixed(2) }}</strong>
        </div>
        <div><div class="muted">Costo por kg</div><strong>{{ report.costPerKg.toFixed(2) }}</strong></div>
        <div><div class="muted">Pérdida poscosecha</div><strong>{{ report.postHarvestLossKg.toFixed(0) }} kg</strong> <span class="muted">({{ report.lossPct.toFixed(1) }}%)</span></div>
        <div v-if="report.quality"><div class="muted">Calidad</div><strong>{{ report.quality }}</strong></div>
        <div><div class="muted">Lote / área</div><strong>{{ report.plotName ?? '—' }}</strong> <span class="muted">{{ report.areaHa.toFixed(2) }} ha</span></div>
      </div>
    </div>

    <div class="card" style="margin-top:16px">
      <h3>Monitoreo fenológico</h3>
      <div class="row" style="align-items:flex-end;gap:8px;flex-wrap:wrap" v-if="cycle.status !== 3">
        <label>Fecha <input v-model="phenoForm.recordedAt" type="date" style="padding:8px" /></label>
        <label>Etapa
          <select v-model.number="phenoForm.stage" style="padding:8px">
            <option v-for="(l, idx) in phenoStages" :key="idx" :value="idx">{{ l }}</option>
          </select>
        </label>
        <label>Altura (cm) <input v-model.number="phenoForm.plantHeightCm" type="number" step="0.1" style="padding:8px;width:90px" /></label>
        <label>Plagas (%) <input v-model.number="phenoForm.pestIncidencePct" type="number" step="0.1" style="padding:8px;width:90px" /></label>
        <label>Enfermedad (%) <input v-model.number="phenoForm.diseaseIncidencePct" type="number" step="0.1" style="padding:8px;width:90px" /></label>
        <label>Notas <input v-model="phenoForm.notes" style="padding:8px" /></label>
        <button @click="addPhenology" style="padding:10px 16px;background:#16a34a;color:#fff;border:none;border-radius:8px;cursor:pointer">Registrar</button>
      </div>

      <table style="margin-top:12px">
        <thead><tr><th>Fecha</th><th>Etapa</th><th>Altura</th><th>Plagas %</th><th>Enferm. %</th><th>Notas</th><th></th></tr></thead>
        <tbody>
          <tr v-for="r in phenology" :key="r.id">
            <td>{{ r.recordedAt }}</td>
            <td>{{ phenoStages[r.stage] }}</td>
            <td>{{ r.plantHeightCm ?? '—' }}</td>
            <td>{{ r.pestIncidencePct ?? '—' }}</td>
            <td>{{ r.diseaseIncidencePct ?? '—' }}</td>
            <td class="muted">{{ r.notes }}</td>
            <td><a href="#" style="color:#dc2626" @click.prevent="removePhenology(r.id)">Eliminar</a></td>
          </tr>
          <tr v-if="!phenology.length"><td colspan="7" class="muted">Sin registros de monitoreo.</td></tr>
        </tbody>
      </table>
    </div>

    <div class="card" style="margin-top:16px" v-if="cycle.status !== 3">
      <h3>Registrar costo / consumo de insumo</h3>
      <div class="row" style="align-items:flex-end;gap:8px;flex-wrap:wrap">
        <label>Tipo
          <select v-model.number="costForm.kind" style="padding:8px">
            <option v-for="(l, idx) in costKind" :key="idx" :value="idx">{{ l }}</option>
          </select>
        </label>
        <label>Insumo (opcional)
          <select v-model="costForm.inputId" style="padding:8px">
            <option value="">— manual —</option>
            <option v-for="i in inputs" :key="i.id" :value="i.id">{{ i.name }} ({{ i.unit }})</option>
          </select>
        </label>
        <label>Cantidad <input v-model.number="costForm.quantity" type="number" step="0.01" style="padding:8px;width:90px" /></label>
        <label v-if="!costForm.inputId">Costo unit. <input v-model.number="costForm.unitCost" type="number" step="0.01" style="padding:8px;width:110px" /></label>
        <label v-else class="muted">Costo unit. (catálogo): {{ (selectedInput?.unitCost ?? 0).toFixed(2) }}</label>
        <label>Descripción <input v-model="costForm.description" style="padding:8px" /></label>
        <div><strong>Total: {{ estimatedTotal.toFixed(2) }}</strong></div>
        <button @click="addCost" style="padding:10px 16px;background:#16a34a;color:#fff;border:none;border-radius:8px;cursor:pointer">Agregar</button>
      </div>

      <table style="margin-top:12px">
        <thead><tr><th>Tipo</th><th>Insumo</th><th>Descripción</th><th>Cant.</th><th>Unit.</th><th>Total</th><th></th></tr></thead>
        <tbody>
          <tr v-for="c in costs" :key="c.id">
            <td>{{ costKind[c.kind] }}</td>
            <td>{{ inputName(c.inputId) }}</td>
            <td class="muted">{{ c.description }}</td>
            <td>{{ c.quantity }}</td>
            <td>{{ c.unitCost.toFixed(2) }}</td>
            <td>{{ c.total.toFixed(2) }}</td>
            <td><a href="#" style="color:#dc2626" @click.prevent="removeCost(c.id)">Eliminar</a></td>
          </tr>
          <tr v-if="!costs.length"><td colspan="7" class="muted">Sin costos aún.</td></tr>
        </tbody>
      </table>
    </div>

    <div class="card" style="margin-top:16px;max-width:520px" v-if="cycle.status !== 3">
      <h3>Cerrar cosecha</h3>
      <div class="row">
        <label>Rendimiento (kg) <input v-model.number="closeForm.yieldKg" type="number" /></label>
        <label>Pérdida poscosecha (kg) <input v-model.number="closeForm.postHarvestLossKg" type="number" /></label>
        <label>Ingreso estimado <input v-model.number="closeForm.revenueEst" type="number" /></label>
        <label>Calidad <input v-model="closeForm.quality" /></label>
      </div>
      <textarea v-model="closeForm.notes" placeholder="Notas" style="width:100%;margin-top:8px"></textarea>
      <button @click="closeCycle" style="margin-top:8px;padding:10px 16px;background:#16a34a;color:#fff;border:none;border-radius:8px;cursor:pointer">
        Cerrar ciclo
      </button>
    </div>
    <div class="card" style="margin-top:16px" v-else>
      <strong>Ciclo cerrado.</strong> Rendimiento: {{ cycle.yieldKg }} kg.
    </div>
  </div>
</template>
