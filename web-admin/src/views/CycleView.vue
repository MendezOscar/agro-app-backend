<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { cyclesApi, inputsApi, type Cycle, type CostSummary, type Cost, type Input } from '../api/resources'

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
        <table>
          <tbody>
            <tr v-for="s in cycle.stages" :key="s.id">
              <td>{{ stageLabels[s.kind] }}</td>
              <td>{{ stageStatus[s.status] }}</td>
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
