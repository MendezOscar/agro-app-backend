<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { analysisApi, type Analysis } from '../api/resources'
import { confirmDialog } from '../composables/dialog'

const route = useRoute()
const router = useRouter()
const plotId = route.params.id as string
const plotName = (route.query.name as string) || 'Lote'

const kindLabels = ['Suelo', 'Agua']
const items = ref<Analysis[]>([])
const form = ref<Omit<Analysis, 'id' | 'plotId'>>({
  kind: 0, ph: null, n: null, p: null, k: null, organicMatter: null, texture: null, sampledAt: null,
})
const error = ref('')

onMounted(load)
async function load() {
  items.value = await analysisApi.byPlot(plotId)
}

async function save() {
  error.value = ''
  try {
    await analysisApi.create(plotId, form.value)
    form.value = { kind: 0, ph: null, n: null, p: null, k: null, organicMatter: null, texture: null, sampledAt: null }
    await load()
  } catch {
    error.value = 'No se pudo guardar el análisis.'
  }
}

async function remove(id: string) {
  if (!(await confirmDialog({ title: 'Eliminar análisis', message: '¿Eliminar este análisis?', danger: true, okText: 'Eliminar' }))) return
  await analysisApi.remove(id)
  await load()
}
</script>

<template>
  <a href="#" @click.prevent="router.back()">← Volver</a>
  <h2>Análisis de {{ plotName }}</h2>
  <div class="row">
    <div class="card" style="flex:2;min-width:420px">
      <table>
        <thead>
          <tr><th>Tipo</th><th>pH</th><th>N</th><th>P</th><th>K</th><th>M.O.</th><th>Textura</th><th>Fecha</th><th></th></tr>
        </thead>
        <tbody>
          <tr v-for="a in items" :key="a.id">
            <td>{{ kindLabels[a.kind] }}</td>
            <td>{{ a.ph ?? '—' }}</td>
            <td>{{ a.n ?? '—' }}</td>
            <td>{{ a.p ?? '—' }}</td>
            <td>{{ a.k ?? '—' }}</td>
            <td>{{ a.organicMatter ?? '—' }}</td>
            <td>{{ a.texture ?? '—' }}</td>
            <td>{{ a.sampledAt ?? '—' }}</td>
            <td><a href="#" style="color:#dc2626" @click.prevent="remove(a.id)">Eliminar</a></td>
          </tr>
          <tr v-if="!items.length"><td colspan="9" class="muted">Sin análisis registrados.</td></tr>
        </tbody>
      </table>
    </div>

    <div class="card" style="flex:1;min-width:280px">
      <h3>Nuevo análisis</h3>
      <form @submit.prevent="save">
        <label>Tipo</label>
        <select v-model.number="form.kind" style="width:100%;margin:4px 0;padding:8px">
          <option :value="0">Suelo</option>
          <option :value="1">Agua</option>
        </select>
        <label>pH <input v-model.number="form.ph" type="number" step="0.1" style="width:100%;margin:4px 0;padding:8px" /></label>
        <label>Nitrógeno (N) <input v-model.number="form.n" type="number" step="0.1" style="width:100%;margin:4px 0;padding:8px" /></label>
        <label>Fósforo (P) <input v-model.number="form.p" type="number" step="0.1" style="width:100%;margin:4px 0;padding:8px" /></label>
        <label>Potasio (K) <input v-model.number="form.k" type="number" step="0.1" style="width:100%;margin:4px 0;padding:8px" /></label>
        <label>Materia orgánica (%) <input v-model.number="form.organicMatter" type="number" step="0.1" style="width:100%;margin:4px 0;padding:8px" /></label>
        <label>Textura <input v-model="form.texture" placeholder="franco, arcilloso..." style="width:100%;margin:4px 0;padding:8px" /></label>
        <label>Fecha de muestreo <input v-model="form.sampledAt" type="date" style="width:100%;margin:4px 0;padding:8px" /></label>
        <p v-if="error" style="color:#dc2626">{{ error }}</p>
        <button style="width:100%;padding:10px;background:#16a34a;color:#fff;border:none;border-radius:8px;cursor:pointer">Guardar</button>
      </form>
    </div>
  </div>
</template>
