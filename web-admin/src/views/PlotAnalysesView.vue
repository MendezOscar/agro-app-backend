<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import Button from 'primevue/button'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import InputText from 'primevue/inputtext'
import InputNumber from 'primevue/inputnumber'
import Select from 'primevue/select'
import Message from 'primevue/message'
import Tag from 'primevue/tag'
import { analysisApi, type Analysis } from '../api/resources'
import { confirmDialog } from '../composables/dialog'
import PageHeader from '../components/PageHeader.vue'
import SectionCard from '../components/SectionCard.vue'
import EmptyState from '../components/EmptyState.vue'

const route = useRoute()
const plotId = route.params.id as string
const plotName = (route.query.name as string) || 'Lote'

const kindLabels = ['Suelo', 'Agua']
const kindOptions = kindLabels.map((label, value) => ({ label, value }))

const items = ref<Analysis[]>([])
const empty = (): Omit<Analysis, 'id' | 'plotId'> =>
  ({ kind: 0, ph: null, n: null, p: null, k: null, organicMatter: null, texture: null, sampledAt: null })
const form = ref(empty())
const error = ref('')

onMounted(load)
async function load() {
  items.value = await analysisApi.byPlot(plotId)
}

async function save() {
  error.value = ''
  try {
    await analysisApi.create(plotId, form.value)
    form.value = empty()
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
  <PageHeader back :title="`Análisis de ${plotName}`" subtitle="Muestras de suelo y agua que alimentan el plan de fertilización." />

  <div class="split">
    <SectionCard title="Historial de muestras" icon="pi-list" :subtitle="`${items.length} análisis`" flush>
      <DataTable :value="items" size="small">
        <template #empty><EmptyState icon="pi-inbox" text="Sin análisis registrados." hint="Agrega el primero desde el formulario." /></template>
        <Column header="Tipo">
          <template #body="{ data }"><Tag :value="kindLabels[data.kind]" :severity="data.kind === 0 ? 'success' : 'info'" /></template>
        </Column>
        <Column header="pH"><template #body="{ data }"><span class="num">{{ data.ph ?? '—' }}</span></template></Column>
        <Column header="N"><template #body="{ data }"><span class="num">{{ data.n ?? '—' }}</span></template></Column>
        <Column header="P"><template #body="{ data }"><span class="num">{{ data.p ?? '—' }}</span></template></Column>
        <Column header="K"><template #body="{ data }"><span class="num">{{ data.k ?? '—' }}</span></template></Column>
        <Column header="M.O."><template #body="{ data }"><span class="num">{{ data.organicMatter ?? '—' }}</span></template></Column>
        <Column header="Textura"><template #body="{ data }">{{ data.texture ?? '—' }}</template></Column>
        <Column header="Muestreo"><template #body="{ data }">{{ data.sampledAt ?? '—' }}</template></Column>
        <Column style="width:3rem">
          <template #body="{ data }">
            <Button icon="pi pi-trash" text rounded severity="danger" aria-label="Eliminar" @click="remove(data.id)" />
          </template>
        </Column>
      </DataTable>
    </SectionCard>

    <SectionCard title="Nuevo análisis" icon="pi-plus-circle">
      <form class="form" @submit.prevent="save">
        <label class="field"><span>Tipo</span>
          <Select v-model="form.kind" :options="kindOptions" option-label="label" option-value="value" />
        </label>
        <div class="field-row">
          <label class="field"><span>pH</span><InputNumber v-model="form.ph" :max-fraction-digits="1" /></label>
          <label class="field"><span>Nitrógeno (N)</span><InputNumber v-model="form.n" :max-fraction-digits="1" /></label>
        </div>
        <div class="field-row">
          <label class="field"><span>Fósforo (P)</span><InputNumber v-model="form.p" :max-fraction-digits="1" /></label>
          <label class="field"><span>Potasio (K)</span><InputNumber v-model="form.k" :max-fraction-digits="2" /></label>
        </div>
        <label class="field"><span>Materia orgánica (%)</span><InputNumber v-model="form.organicMatter" :max-fraction-digits="1" /></label>
        <label class="field"><span>Textura</span><InputText v-model="form.texture" placeholder="franco, franco arcilloso…" /></label>
        <label class="field"><span>Fecha de muestreo</span><InputText v-model="form.sampledAt" type="date" /></label>
        <Message v-if="error" severity="error" :closable="false">{{ error }}</Message>
        <Button type="submit" label="Guardar análisis" icon="pi pi-check" />
      </form>
    </SectionCard>
  </div>
</template>

<style scoped>
.form { display: flex; flex-direction: column; gap: 14px; }
</style>
