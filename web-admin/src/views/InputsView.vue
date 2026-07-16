<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { inputsApi, type Input } from '../api/resources'

const kindLabels = ['Semilla', 'Fertilizante', 'Plaguicida', 'Maquinaria', 'Mano de obra']
const inputs = ref<Input[]>([])
const form = ref<Omit<Input, 'id'>>({ name: '', kind: 0, unit: '', unitCost: 0, stockQty: 0, minStock: 0 })
const editingId = ref<string | null>(null)
const error = ref('')

onMounted(load)
async function load() {
  inputs.value = await inputsApi.list()
}

function reset() {
  form.value = { name: '', kind: 0, unit: '', unitCost: 0, stockQty: 0, minStock: 0 }
  editingId.value = null
  error.value = ''
}

function edit(i: Input) {
  editingId.value = i.id
  form.value = { name: i.name, kind: i.kind, unit: i.unit, unitCost: i.unitCost, stockQty: i.stockQty, minStock: i.minStock }
}

async function restock(i: Input) {
  const q = prompt(`Entrada de inventario para ${i.name} (${i.unit}). Cantidad a agregar:`, '0')
  if (q == null) return
  const n = Number(q)
  if (!Number.isFinite(n) || n === 0) return
  await inputsApi.restock(i.id, n)
  await load()
}

const low = (i: Input) => i.minStock > 0 && i.stockQty <= i.minStock

async function save() {
  error.value = ''
  try {
    if (editingId.value) await inputsApi.update(editingId.value, form.value)
    else await inputsApi.create(form.value)
    reset()
    await load()
  } catch {
    error.value = 'No se pudo guardar el insumo.'
  }
}

async function remove(id: string) {
  if (!confirm('¿Eliminar este insumo?')) return
  await inputsApi.remove(id)
  await load()
}
</script>

<template>
  <h2>Insumos</h2>
  <div class="row">
    <div class="card" style="flex:2;min-width:360px">
      <table>
        <thead><tr><th>Nombre</th><th>Tipo</th><th>Unidad</th><th>Costo unit.</th><th>Stock</th><th></th></tr></thead>
        <tbody>
          <tr v-for="i in inputs" :key="i.id">
            <td>{{ i.name }}</td>
            <td>{{ kindLabels[i.kind] }}</td>
            <td>{{ i.unit }}</td>
            <td>{{ i.unitCost.toFixed(2) }}</td>
            <td :style="{ fontWeight: 600, color: low(i) ? '#dc2626' : 'inherit' }">
              {{ i.stockQty.toLocaleString('es', { maximumFractionDigits: 2 }) }}
              <span v-if="low(i)" title="Stock bajo">⚠️</span>
            </td>
            <td style="white-space:nowrap">
              <a href="#" @click.prevent="restock(i)">+ Entrada</a> ·
              <a href="#" @click.prevent="edit(i)">Editar</a> ·
              <a href="#" style="color:#dc2626" @click.prevent="remove(i.id)">Eliminar</a>
            </td>
          </tr>
          <tr v-if="!inputs.length"><td colspan="6" class="muted">Sin insumos aún.</td></tr>
        </tbody>
      </table>
    </div>

    <div class="card" style="flex:1;min-width:280px">
      <h3>{{ editingId ? 'Editar insumo' : 'Nuevo insumo' }}</h3>
      <form @submit.prevent="save">
        <label class="fld">Nombre
          <input v-model="form.name" placeholder="ej. Urea 46%" />
        </label>
        <label class="fld">Tipo
          <select v-model.number="form.kind">
            <option v-for="(l, idx) in kindLabels" :key="idx" :value="idx">{{ l }}</option>
          </select>
        </label>
        <label class="fld">Unidad
          <input v-model="form.unit" placeholder="kg, L, hora, saco..." />
        </label>
        <label class="fld">Costo unitario
          <input v-model.number="form.unitCost" type="number" step="0.01" />
        </label>
        <label class="fld">Stock actual
          <input v-model.number="form.stockQty" type="number" step="0.01" />
        </label>
        <label class="fld">Stock mínimo <span class="muted">(alerta de stock bajo)</span>
          <input v-model.number="form.minStock" type="number" step="0.01" />
        </label>
        <p v-if="error" style="color:#dc2626">{{ error }}</p>
        <button style="width:100%;padding:10px;background:#16a34a;color:#fff;border:none;border-radius:8px;cursor:pointer">
          {{ editingId ? 'Guardar cambios' : 'Crear' }}
        </button>
        <button v-if="editingId" type="button" @click="reset" style="width:100%;padding:8px;margin-top:6px;background:#e5e7eb;border:none;border-radius:8px;cursor:pointer">
          Cancelar
        </button>
      </form>
    </div>
  </div>
</template>

<style scoped>
.fld {
  display: block;
  font-size: 13px;
  font-weight: 600;
  color: #444;
  margin: 10px 0 0;
}
.fld input,
.fld select {
  width: 100%;
  margin: 4px 0 0;
  padding: 8px;
  font-weight: 400;
}
</style>
