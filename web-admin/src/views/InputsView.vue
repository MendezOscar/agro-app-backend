<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import Button from 'primevue/button'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import InputNumber from 'primevue/inputnumber'
import Select from 'primevue/select'
import Message from 'primevue/message'
import Tag from 'primevue/tag'
import IconField from 'primevue/iconfield'
import InputIcon from 'primevue/inputicon'
import { inputsApi, type Input } from '../api/resources'
import { confirmDialog } from '../composables/dialog'
import { money, num } from '../utils/format'
import PageHeader from '../components/PageHeader.vue'
import SectionCard from '../components/SectionCard.vue'
import EmptyState from '../components/EmptyState.vue'

const kindLabels = ['Semilla', 'Fertilizante', 'Plaguicida', 'Maquinaria', 'Mano de obra']
const kindOptions = kindLabels.map((label, value) => ({ label, value }))

const inputs = ref<Input[]>([])
const search = ref('')
const error = ref('')

const empty = (): Omit<Input, 'id'> => ({ name: '', kind: 0, unit: '', unitCost: 0, stockQty: 0, minStock: 0 })
const form = ref<Omit<Input, 'id'>>(empty())
const editingId = ref<string | null>(null)
const formOpen = ref(false)

onMounted(load)
async function load() {
  inputs.value = await inputsApi.list()
}

const low = (i: Input) => i.minStock > 0 && i.stockQty <= i.minStock
const lowCount = computed(() => inputs.value.filter(low).length)
const filtered = computed(() => {
  const q = search.value.trim().toLowerCase()
  if (!q) return inputs.value
  return inputs.value.filter((i) => i.name.toLowerCase().includes(q) || kindLabels[i.kind].toLowerCase().includes(q))
})

function openNew() {
  form.value = empty()
  editingId.value = null
  error.value = ''
  formOpen.value = true
}
function openEdit(i: Input) {
  form.value = { name: i.name, kind: i.kind, unit: i.unit, unitCost: i.unitCost, stockQty: i.stockQty, minStock: i.minStock }
  editingId.value = i.id
  error.value = ''
  formOpen.value = true
}

async function save() {
  error.value = ''
  const f = form.value
  if (!f.name.trim()) { error.value = 'El nombre es obligatorio.'; return }
  if (!f.unit.trim()) { error.value = 'La unidad es obligatoria (quintal, litro, jornal…).'; return }
  if (f.unitCost < 0 || f.stockQty < 0 || f.minStock < 0) { error.value = 'Los valores no pueden ser negativos.'; return }
  try {
    if (editingId.value) await inputsApi.update(editingId.value, f)
    else await inputsApi.create(f)
    formOpen.value = false
    await load()
  } catch {
    error.value = 'No se pudo guardar el insumo.'
  }
}

// Entrada de inventario
const restockFor = ref<Input | null>(null)
const restockQty = ref<number>(0)
function openRestock(i: Input) { restockFor.value = i; restockQty.value = 0 }
async function confirmRestock() {
  const i = restockFor.value
  if (!i || !Number.isFinite(restockQty.value) || restockQty.value === 0) { restockFor.value = null; return }
  await inputsApi.restock(i.id, restockQty.value)
  restockFor.value = null
  await load()
}

async function remove(i: Input) {
  if (!(await confirmDialog({ title: 'Eliminar insumo', message: `¿Eliminar "${i.name}"?`, danger: true, okText: 'Eliminar' }))) return
  await inputsApi.remove(i.id)
  await load()
}
</script>

<template>
  <PageHeader title="Insumos" subtitle="Catálogo y existencias del almacén, con alerta de stock bajo.">
    <template #actions>
      <Button label="Nuevo insumo" icon="pi pi-plus" @click="openNew" />
    </template>
  </PageHeader>

  <Message v-if="lowCount" severity="warn" :closable="false" class="mb">
    {{ lowCount }} insumo(s) están en o por debajo de su stock mínimo.
  </Message>

  <SectionCard title="Catálogo" icon="pi-box" :subtitle="`${inputs.length} insumo(s)`" flush>
    <template #actions>
      <IconField>
        <InputIcon class="pi pi-search" />
        <InputText v-model="search" placeholder="Buscar insumo…" size="small" />
      </IconField>
    </template>

    <DataTable :value="filtered" size="small" paginator :rows="12" removable-sort>
      <template #empty><EmptyState icon="pi-box" text="Sin insumos que mostrar." /></template>
      <Column field="name" header="Nombre" sortable>
        <template #body="{ data }"><strong>{{ data.name }}</strong></template>
      </Column>
      <Column header="Tipo" sortable field="kind">
        <template #body="{ data }">{{ kindLabels[data.kind] }}</template>
      </Column>
      <Column field="unit" header="Unidad" />
      <Column header="Costo unitario" sortable field="unitCost">
        <template #body="{ data }"><span class="num">{{ money(data.unitCost, 2) }}</span></template>
      </Column>
      <Column header="Stock" sortable field="stockQty">
        <template #body="{ data }">
          <span class="num" :class="{ low: low(data) }">{{ num(data.stockQty, 2) }}</span>
          <Tag v-if="low(data)" value="Bajo" severity="danger" class="ml" />
        </template>
      </Column>
      <Column header="Mínimo">
        <template #body="{ data }"><span class="num muted">{{ num(data.minStock, 2) }}</span></template>
      </Column>
      <Column style="width:11rem">
        <template #body="{ data }">
          <div class="acts">
            <Button icon="pi pi-plus-circle" text rounded severity="secondary" v-tooltip.top="'Entrada'" @click="openRestock(data)" />
            <Button icon="pi pi-pencil" text rounded severity="secondary" v-tooltip.top="'Editar'" @click="openEdit(data)" />
            <Button icon="pi pi-trash" text rounded severity="danger" v-tooltip.top="'Eliminar'" @click="remove(data)" />
          </div>
        </template>
      </Column>
    </DataTable>
  </SectionCard>

  <!-- Alta / edición -->
  <Dialog v-model:visible="formOpen" modal :draggable="false" :header="editingId ? 'Editar insumo' : 'Nuevo insumo'" :style="{ width: '30rem' }">
    <form class="dlg-form" @submit.prevent="save">
      <label class="field"><span>Nombre</span><InputText v-model="form.name" placeholder="ej. Urea 46%" autofocus /></label>
      <div class="field-row">
        <label class="field"><span>Tipo</span>
          <Select v-model="form.kind" :options="kindOptions" option-label="label" option-value="value" />
        </label>
        <label class="field"><span>Unidad</span><InputText v-model="form.unit" placeholder="quintal, litro, jornal…" /></label>
      </div>
      <div class="field-row">
        <label class="field"><span>Costo unitario (L)</span><InputNumber v-model="form.unitCost" :max-fraction-digits="2" /></label>
        <label class="field"><span>Stock actual</span><InputNumber v-model="form.stockQty" :max-fraction-digits="2" /></label>
        <label class="field"><span>Stock mínimo</span><InputNumber v-model="form.minStock" :max-fraction-digits="2" /></label>
      </div>
      <p class="tiny">El stock mínimo activa la alerta de reposición en el panel.</p>
      <Message v-if="error" severity="error" :closable="false">{{ error }}</Message>
    </form>
    <template #footer>
      <Button label="Cancelar" severity="secondary" text @click="formOpen = false" />
      <Button :label="editingId ? 'Guardar cambios' : 'Crear insumo'" @click="save" />
    </template>
  </Dialog>

  <!-- Entrada de inventario -->
  <Dialog :visible="!!restockFor" modal :draggable="false" header="Entrada de inventario" :style="{ width: '24rem' }" @update:visible="restockFor = null">
    <label class="field">
      <span>Cantidad a agregar ({{ restockFor?.unit }})</span>
      <InputNumber v-model="restockQty" :max-fraction-digits="2" autofocus />
    </label>
    <p class="muted stock-preview">
      Stock actual <strong class="num">{{ num(restockFor?.stockQty, 2) }}</strong>
      → nuevo <strong class="num">{{ num((restockFor?.stockQty ?? 0) + (restockQty || 0), 2) }}</strong>
    </p>
    <template #footer>
      <Button label="Cancelar" severity="secondary" text @click="restockFor = null" />
      <Button label="Agregar" @click="confirmRestock" />
    </template>
  </Dialog>
</template>

<style scoped>
.mb { margin-bottom: 16px; }
.ml { margin-left: 6px; }
.low { color: var(--danger); font-weight: 700; }
.acts { display: flex; justify-content: flex-end; }
.dlg-form { display: flex; flex-direction: column; gap: 14px; }
.stock-preview { margin: 14px 0 0; }
</style>
