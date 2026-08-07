<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { harvestApi } from '../api/resources'
import { alertDialog } from '../composables/dialog'

const route = useRoute()
const crop = ref<string>((route.query.crop as string) || 'Café')
const steps = ref<string[]>([])
const isCustom = ref(false)
const loading = ref(false)
const commonCrops = ['Café', 'Maíz', 'Arroz', 'Frijol', 'Papa', 'Trigo', 'Tomate']

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
  steps.value = [...t.steps]; isCustom.value = true
  await alertDialog('Plantilla guardada para ' + crop.value.trim() + '.')
}
async function reset() {
  const t = await harvestApi.resetTemplate(crop.value.trim())
  steps.value = [...t.steps]; isCustom.value = false
}
</script>

<template>
  <h2>Proceso de cosecha</h2>
  <p class="muted" style="margin-top:6px">Define los pasos de cosecha por cultivo. Se aplican a los ciclos nuevos de ese cultivo; cada cliente puede tener los suyos.</p>

  <div class="card" style="margin-top:16px;max-width:640px">
    <div class="row" style="display:flex;gap:12px;align-items:flex-end;flex-wrap:wrap">
      <label style="flex:1;min-width:200px">Cultivo
        <input v-model="crop" list="crops" @change="load" style="width:100%" />
        <datalist id="crops"><option v-for="c in commonCrops" :key="c" :value="c" /></datalist>
      </label>
      <span class="tag" :class="isCustom ? 'tag-custom' : 'tag-default'">{{ isCustom ? 'Personalizado' : 'Por defecto' }}</span>
    </div>

    <div v-if="loading" class="muted" style="margin-top:14px">Cargando…</div>
    <div v-else style="margin-top:14px">
      <div class="step-row" v-for="i in steps.length" :key="i">
        <span class="idx">{{ i }}</span>
        <input v-model="steps[i - 1]" placeholder="Nombre del paso" />
        <button class="mini" title="Subir" @click="move(i - 1, -1)" :disabled="i === 1">↑</button>
        <button class="mini" title="Bajar" @click="move(i - 1, 1)" :disabled="i === steps.length">↓</button>
        <button class="mini danger" title="Quitar" @click="removeStep(i - 1)">✕</button>
      </div>
      <button class="btn btn-sm" style="margin-top:8px" @click="addStep">+ Agregar paso</button>
    </div>

    <div style="margin-top:18px;display:flex;gap:10px">
      <button class="btn" @click="save">Guardar plantilla</button>
      <button class="btn-ghost" v-if="isCustom" @click="reset">Restablecer al por defecto</button>
    </div>
  </div>
</template>

<style scoped>
.tag { padding: 4px 10px; border-radius: 20px; font-size: 12px; font-weight: 700; }
.tag-custom { background: #dcefe0; color: #15803d; }
.tag-default { background: #eef1ec; color: #5d6b60; }
.step-row { display: flex; align-items: center; gap: 8px; margin-bottom: 8px; }
.step-row .idx { width: 22px; height: 22px; border-radius: 50%; background: var(--leaf, #2f7a3a); color: #fff; display: grid; place-items: center; font-size: 12px; font-weight: 700; flex-shrink: 0; }
.step-row input { flex: 1; padding: 7px 10px; border: 1px solid var(--border, #e0e6dd); border-radius: 8px; }
.mini { width: 30px; height: 32px; border: 1px solid var(--border, #e0e6dd); background: #fff; border-radius: 8px; cursor: pointer; }
.mini:disabled { opacity: .4; cursor: default; }
.mini.danger { color: #dc2626; }
</style>
