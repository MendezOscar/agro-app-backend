<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Tag from 'primevue/tag'
import Message from 'primevue/message'
import { harvestApi } from '../api/resources'
import { alertDialog, confirmDialog } from '../composables/dialog'
import PageHeader from '../components/PageHeader.vue'
import SectionCard from '../components/SectionCard.vue'

const route = useRoute()
const crop = ref<string>((route.query.crop as string) || 'Café')
const steps = ref<string[]>([])
const isCustom = ref(false)
const loading = ref(false)
const commonCrops = ['Café', 'Maíz', 'Frijol', 'Arroz', 'Papa', 'Tomate', 'Caña']

async function load() {
  if (!crop.value.trim()) return
  loading.value = true
  try {
    const t = await harvestApi.getTemplate(crop.value.trim())
    steps.value = [...t.steps]
    isCustom.value = t.isCustom
  } finally { loading.value = false }
}
onMounted(load)

function pickCrop(c: string) { crop.value = c; load() }
function addStep() { steps.value.push('') }
function removeStep(i: number) { steps.value.splice(i, 1) }
function move(i: number, dir: -1 | 1) {
  const j = i + dir
  if (j < 0 || j >= steps.value.length) return
  const arr = steps.value
  ;[arr[i], arr[j]] = [arr[j], arr[i]]
}
async function save() {
  const clean = steps.value.map((s) => s.trim()).filter((s) => s.length > 0)
  if (clean.length === 0) { await alertDialog('Agrega al menos un paso.'); return }
  const t = await harvestApi.saveTemplate(crop.value.trim(), clean)
  steps.value = [...t.steps]
  isCustom.value = true
  await alertDialog(`Plantilla guardada para ${crop.value.trim()}.`)
}
async function reset() {
  if (!(await confirmDialog({
    title: 'Restablecer plantilla',
    message: 'Se descartarán los pasos personalizados y volverán los del sistema para este cultivo.',
    okText: 'Restablecer', danger: true,
  }))) return
  const t = await harvestApi.resetTemplate(crop.value.trim())
  steps.value = [...t.steps]
  isCustom.value = false
}
</script>

<template>
  <PageHeader
    title="Proceso de cosecha"
    subtitle="Define los pasos de beneficio por cultivo. Se aplican a los ciclos nuevos y cada cliente puede tener los suyos."
  />

  <div class="split">
    <SectionCard title="Pasos del proceso" icon="pi-sliders-h">
      <template #actions>
        <Tag :value="isCustom ? 'Personalizado' : 'Por defecto'" :severity="isCustom ? 'success' : 'secondary'" />
      </template>

      <label class="field crop">
        <span>Cultivo</span>
        <InputText v-model="crop" @change="load" />
      </label>
      <div class="chips">
        <button v-for="c in commonCrops" :key="c" class="chip" :class="{ on: crop === c }" @click="pickCrop(c)">{{ c }}</button>
      </div>

      <div v-if="loading" class="muted">Cargando…</div>
      <template v-else>
        <div class="step" v-for="(_, i) in steps" :key="i">
          <span class="idx">{{ i + 1 }}</span>
          <InputText v-model="steps[i]" placeholder="Nombre del paso" class="grow" />
          <Button icon="pi pi-arrow-up" text rounded severity="secondary" :disabled="i === 0" aria-label="Subir" @click="move(i, -1)" />
          <Button icon="pi pi-arrow-down" text rounded severity="secondary" :disabled="i === steps.length - 1" aria-label="Bajar" @click="move(i, 1)" />
          <Button icon="pi pi-times" text rounded severity="danger" aria-label="Quitar" @click="removeStep(i)" />
        </div>
        <Button label="Agregar paso" icon="pi pi-plus" text @click="addStep" />

        <div class="actions">
          <Button label="Guardar plantilla" icon="pi pi-check" @click="save" />
          <Button v-if="isCustom" label="Restablecer" severity="secondary" outlined @click="reset" />
        </div>
      </template>
    </SectionCard>

    <SectionCard title="Cómo funciona" icon="pi-info-circle">
      <Message severity="info" :closable="false">
        Los pasos se materializan al abrir la etapa de cosecha de un ciclo. Cambiarlos aquí no altera los ciclos que ya
        los tienen creados.
      </Message>
      <ul class="tips">
        <li>Cada paso registra cuánto entra y cuánto sale, y la app calcula la merma.</li>
        <li>Si no guardas una plantilla, el sistema usa los pasos por defecto del cultivo.</li>
        <li>Para café la secuencia habitual es corte, despulpe, fermentado, lavado, secado, trilla y empacado.</li>
      </ul>
    </SectionCard>
  </div>
</template>

<style scoped>
.crop { max-width: 260px; }
.chips { display: flex; flex-wrap: wrap; gap: 6px; margin: 10px 0 18px; }
.chip {
  border: 1px solid var(--border); background: var(--surface); border-radius: 999px; padding: 4px 12px;
  font: inherit; font-size: 12.5px; font-weight: 600; color: var(--muted); cursor: pointer;
}
.chip:hover { border-color: var(--leaf); }
.chip.on { background: #eaf3ea; border-color: var(--leaf); color: var(--leaf-dark); }
.step { display: flex; align-items: center; gap: 6px; margin-bottom: 8px; }
.step .idx {
  width: 24px; height: 24px; border-radius: 50%; background: var(--leaf); color: #fff;
  display: grid; place-items: center; font-size: 12px; font-weight: 700; flex-shrink: 0;
}
.grow { flex: 1; }
.actions { display: flex; gap: 10px; margin-top: 20px; padding-top: 16px; border-top: 1px solid var(--border); }
.tips { margin: 14px 0 0; padding-left: 18px; color: var(--muted); font-size: 13.5px; line-height: 1.7; }
</style>
