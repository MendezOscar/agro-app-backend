<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { cyclesApi, type Cycle, type CostSummary } from '../api/resources'

const stageLabels = ['Planificación', 'Prep. suelo', 'Siembra', 'Manejo', 'Monitoreo', 'Cosecha', 'Poscosecha', 'Evaluación']
const stageStatus = ['Pendiente', 'En progreso', 'Completada']
const cycleStatus = ['Planificada', 'Activa', 'Cosechada', 'Cerrada']
const costKind = ['Mano de obra', 'Insumo', 'Maquinaria', 'Otro']

const route = useRoute()
const id = route.params.id as string
const cycle = ref<Cycle | null>(null)
const summary = ref<CostSummary | null>(null)

const closeForm = ref({ yieldKg: 0, quality: '', postHarvestLossKg: 0, revenueEst: 0, notes: '' })

onMounted(load)
async function load() {
  cycle.value = await cyclesApi.get(id)
  summary.value = await cyclesApi.costSummary(id)
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
