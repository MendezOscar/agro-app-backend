<script setup lang="ts">
import { onMounted, ref, shallowRef } from 'vue'
import { useRouter } from 'vue-router'
import maplibregl from 'maplibre-gl'
// @ts-expect-error: sin tipos; MapboxDraw es compatible con MapLibre en runtime
import MapboxDraw from '@mapbox/mapbox-gl-draw'
import Button from 'primevue/button'
import SelectButton from 'primevue/selectbutton'
import Message from 'primevue/message'
import Tag from 'primevue/tag'
import { farmsApi, cyclesApi, type Farm, type Plot, type Cycle } from '../api/resources'
import { confirmDialog, alertDialog } from '../composables/dialog'
import PageHeader from '../components/PageHeader.vue'
import SectionCard from '../components/SectionCard.vue'
import EmptyState from '../components/EmptyState.vue'
import PromptDialog from '../components/PromptDialog.vue'

// Diálogo de texto reutilizable (reemplaza el prompt del navegador)
const prompt = ref<null | { title: string; label: string; okText: string; onOk: (v: string) => void | Promise<void> }>(null)
const promptValue = ref('')
function openPrompt(title: string, label: string, value: string, onOk: (v: string) => void | Promise<void>, okText = 'Guardar') {
  prompt.value = { title, label, okText, onOk }
  promptValue.value = value
}
async function promptOk() {
  const s = prompt.value
  if (!s) return
  const v = promptValue.value.trim()
  prompt.value = null
  if (v) await s.onOk(v)
}

const token = import.meta.env.VITE_MAPTILER_KEY as string
const router = useRouter()

const farms = ref<Farm[]>([])
const selectedFarm = ref<Farm | null>(null)
const plots = ref<Plot[]>([])
const cyclesByPlot = ref<Record<string, Cycle[]>>({})
const drawMode = ref<'farm' | 'plot'>('farm')
const drawModes = [
  { label: 'Finca', value: 'farm' },
  { label: 'Lote', value: 'plot' },
]
const editing = ref<{ kind: 'farm' | 'plot'; id: string; name: string } | null>(null)

const mapEl = ref<HTMLDivElement | null>(null)
const map = shallowRef<maplibregl.Map | null>(null)
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const draw = shallowRef<any>(null)

const cycleStatusLabels = ['Planificada', 'Activa', 'Cosechada', 'Cerrada']
const cycleSeverity = ['secondary', 'success', 'warn', 'contrast'] as const
const plotActiveCycle = (plotId: string) => (cyclesByPlot.value[plotId] || []).find((c) => c.status === 1)

onMounted(async () => {
  farms.value = await farmsApi.list()
  if (token) initMap()
  if (!token && farms.value.length) await selectFarm(farms.value[0]) // sin mapa: igual pobla el panel
})

function initMap() {
  const m = new maplibregl.Map({
    container: mapEl.value!,
    style: `https://api.maptiler.com/maps/hybrid/style.json?key=${token}`,
    center: [-87.2068, 14.0818], // Tegucigalpa, Honduras
    zoom: 7,
  })
  m.addControl(new maplibregl.NavigationControl({ showCompass: true }), 'top-right')
  const d = new MapboxDraw({ displayControlsDefault: false, controls: { polygon: true, trash: true } })
  m.addControl(d as maplibregl.IControl)
  m.on('draw.create', onDraw)
  m.on('draw.update', onEdit)
  m.on('load', () => {
    renderFarms()
    if (farms.value.length) selectFarm(farms.value[0]) // auto-selecciona la primera finca
  })
  map.value = m
  draw.value = d
}

function renderFarms() {
  for (const f of farms.value) {
    if (!f.boundary) continue
    addPolygonLayer(`farm-${f.id}`, f.boundary, '#22c55e')
  }
}

function addPolygonLayer(id: string, ring: number[][], color: string) {
  const m = map.value
  if (!m) return
  if (m.getSource(id)) {
    // Actualiza la geometría si ya existe (tras editar).
    const src = m.getSource(id) as maplibregl.GeoJSONSource
    src.setData({ type: 'Feature', properties: {}, geometry: { type: 'Polygon', coordinates: [ring] } })
    return
  }
  m.addSource(id, {
    type: 'geojson',
    data: { type: 'Feature', properties: {}, geometry: { type: 'Polygon', coordinates: [ring] } },
  })
  m.addLayer({ id: `${id}-fill`, type: 'fill', source: id, paint: { 'fill-color': color, 'fill-opacity': 0.3 } })
  m.addLayer({ id: `${id}-line`, type: 'line', source: id, paint: { 'line-color': color, 'line-width': 2 } })
}

function removePolygonLayer(id: string) {
  const m = map.value
  if (!m) return
  for (const suffix of ['-fill', '-line']) {
    if (m.getLayer(`${id}${suffix}`)) m.removeLayer(`${id}${suffix}`)
  }
  if (m.getSource(id)) m.removeSource(id)
}

/// Carga la geometría existente en la herramienta de dibujo para editarla.
function editOnMap(kind: 'farm' | 'plot', id: string, name: string, ring: number[][] | null) {
  if (!ring || !draw.value || !map.value) return
  draw.value.deleteAll()
  removePolygonLayer(`${kind}-${id}`) // evita solaparse con la capa estática
  const ids = draw.value.add({
    type: 'Feature',
    properties: { kind, entityId: id },
    geometry: { type: 'Polygon', coordinates: [ring] },
  })
  draw.value.changeMode('direct_select', { featureId: ids[0] })
  editing.value = { kind, id, name }
  const center = ring[0] as [number, number]
  map.value.flyTo({ center, zoom: 15 })
}

async function onEdit(e: {
  features: Array<{ properties: { kind: 'farm' | 'plot'; entityId: string }; geometry: { coordinates: number[][][] } }>
}) {
  const f = e.features[0]
  const ring = f.geometry.coordinates[0]
  const { kind, entityId } = f.properties
  const name = editing.value?.name ?? ''
  if (kind === 'farm') {
    await farmsApi.update(entityId, { name, boundary: ring, location: ring[0] })
  } else {
    const soilType = plots.value.find((p) => p.id === entityId)?.soilType ?? null
    await farmsApi.updatePlot(entityId, { name, boundary: ring, soilType })
  }
}

async function finishEdit() {
  draw.value?.deleteAll()
  editing.value = null
  farms.value = await farmsApi.list()
  renderFarms()
  if (selectedFarm.value) await selectFarm(selectedFarm.value)
}

function renameFarm(f: Farm) {
  openPrompt('Renombrar finca', 'Nombre de la finca', f.name, async (name) => {
    if (name === f.name) return
    await farmsApi.update(f.id, { name, boundary: f.boundary, location: f.location })
    farms.value = await farmsApi.list()
  })
}

async function deleteFarm(f: Farm) {
  if (!(await confirmDialog({ title: 'Eliminar finca', message: `¿Eliminar la finca "${f.name}" y todo su contenido?`, danger: true, okText: 'Eliminar' }))) return
  await farmsApi.remove(f.id)
  removePolygonLayer(`farm-${f.id}`)
  if (selectedFarm.value?.id === f.id) selectedFarm.value = null
  farms.value = await farmsApi.list()
}

async function deletePlot(p: Plot) {
  if (!(await confirmDialog({ title: 'Eliminar lote', message: `¿Eliminar el lote "${p.name}"?`, danger: true, okText: 'Eliminar' }))) return
  await farmsApi.removePlot(p.id)
  removePolygonLayer(`plot-${p.id}`)
  if (selectedFarm.value) await selectFarm(selectedFarm.value)
}

async function onDraw(e: { features: Array<{ geometry: { coordinates: number[][][] } }> }) {
  const ring = e.features[0].geometry.coordinates[0]
  draw.value?.deleteAll()
  if (drawMode.value === 'plot' && !selectedFarm.value) {
    await alertDialog('Selecciona primero una finca para dibujar un lote.')
    return
  }
  const isFarm = drawMode.value === 'farm'
  openPrompt(isFarm ? 'Nueva finca' : 'Nuevo lote', isFarm ? 'Nombre de la finca' : 'Nombre del lote', '', async (name) => {
    if (isFarm) {
      await farmsApi.create({ name, boundary: ring, location: ring[0] })
      farms.value = await farmsApi.list()
      renderFarms()
    } else if (selectedFarm.value) {
      await farmsApi.createPlot(selectedFarm.value.id, { name, boundary: ring })
      await selectFarm(selectedFarm.value)
    }
  }, 'Crear')
}

async function selectFarm(f: Farm) {
  selectedFarm.value = f
  plots.value = await farmsApi.plots(f.id)
  for (const p of plots.value) {
    cyclesByPlot.value[p.id] = await cyclesApi.byPlot(p.id)
    // Verde si el lote tiene un ciclo activo; ámbar si no.
    const color = plotActiveCycle(p.id) ? '#16a34a' : '#f59e0b'
    if (p.boundary) addPolygonLayer(`plot-${p.id}`, p.boundary, color)
  }
  if (f.location && map.value) map.value.flyTo({ center: f.location as [number, number], zoom: 14 })
}

/// Activa el modo de dibujo de polígono (más fiable que el ícono del control).
async function startDraw() {
  if (drawMode.value === 'plot' && !selectedFarm.value) {
    await alertDialog('Selecciona primero una finca para dibujar un lote.')
    return
  }
  draw.value?.changeMode('draw_polygon')
}

function newCycle(plot: Plot) {
  openPrompt('Nuevo ciclo', 'Cultivo (ej. Café)', '', async (crop) => {
    await cyclesApi.create({ plotId: plot.id, crop })
    cyclesByPlot.value[plot.id] = await cyclesApi.byPlot(plot.id)
  }, 'Crear')
}
</script>

<template>
  <PageHeader title="Fincas y lotes" subtitle="Dibuja los polígonos en el mapa y gestiona los ciclos de cada lote." />

  <div class="split">
    <!-- Mapa -->
    <SectionCard title="Mapa" icon="pi-map">
      <template #actions>
        <template v-if="token">
          <SelectButton v-model="drawMode" :options="drawModes" option-label="label" option-value="value" size="small" />
          <Button label="Dibujar" icon="pi pi-pencil" size="small" @click="startDraw" />
        </template>
      </template>

      <Message v-if="!token" severity="warn" :closable="false">
        Configura <code>VITE_MAPTILER_KEY</code> en el archivo <code>.env</code> para habilitar el mapa.
      </Message>
      <template v-else>
        <p class="tiny hint">
          Traza el polígono y haz doble clic para cerrarlo. El modo <strong>Lote</strong> lo asigna a la finca seleccionada.
        </p>
        <Message v-if="editing" severity="warn" :closable="false" class="editing">
          Editando <strong>{{ editing.name }}</strong>: arrastra los vértices en el mapa.
          <Button label="Terminar" size="small" class="ml" @click="finishEdit" />
        </Message>
        <div ref="mapEl" class="map" />
      </template>
    </SectionCard>

    <!-- Panel lateral -->
    <div class="stack">
      <SectionCard title="Fincas" icon="pi-home" :subtitle="`${farms.length} registrada(s)`">
        <EmptyState v-if="!farms.length" icon="pi-map" text="Sin fincas todavía." hint="Dibuja la primera en el mapa." />
        <button
          v-for="f in farms" :key="f.id" class="pick" :class="{ on: selectedFarm?.id === f.id }"
          @click="selectFarm(f)"
        >
          <div class="pick-top">
            <strong>{{ f.name }}</strong>
            <span class="muted num">{{ f.areaHa.toFixed(1) }} ha</span>
          </div>
          <div class="pick-actions">
            <Button label="Editar mapa" size="small" text @click.stop="editOnMap('farm', f.id, f.name, f.boundary)" />
            <Button label="Renombrar" size="small" text severity="secondary" @click.stop="renameFarm(f)" />
            <Button label="Eliminar" size="small" text severity="danger" @click.stop="deleteFarm(f)" />
          </div>
        </button>
      </SectionCard>

      <SectionCard
        v-if="selectedFarm" :title="`Lotes de ${selectedFarm.name}`" icon="pi-th-large"
        :subtitle="`${plots.length} lote(s)`"
      >
        <EmptyState v-if="!plots.length" icon="pi-th-large" text="Sin lotes." hint="Cambia a modo Lote y dibújalo en el mapa." />
        <article v-for="p in plots" :key="p.id" class="plot" :class="{ on: plotActiveCycle(p.id) }">
          <div class="plot-top">
            <span class="dot" :class="{ active: plotActiveCycle(p.id) }" />
            <strong>{{ p.name }}</strong>
            <span style="flex:1" />
            <span class="muted num">{{ p.areaHa.toFixed(2) }} ha</span>
          </div>
          <p v-if="p.soilType" class="tiny">Suelo {{ p.soilType }}</p>

          <div class="cycles">
            <button
              v-for="c in cyclesByPlot[p.id] || []" :key="c.id" class="cycle-chip"
              @click="router.push({ name: 'cycle', params: { id: c.id } })"
            >
              <Tag :value="cycleStatusLabels[c.status]" :severity="cycleSeverity[c.status]" />
              <span>{{ c.crop }}</span>
            </button>
            <Button label="Ciclo" icon="pi pi-plus" size="small" outlined @click="newCycle(p)" />
          </div>

          <div class="plot-actions">
            <Button label="Análisis" size="small" text @click="router.push({ name: 'analyses', params: { id: p.id }, query: { name: p.name } })" />
            <Button label="Editar mapa" size="small" text severity="secondary" @click="editOnMap('plot', p.id, p.name, p.boundary)" />
            <Button label="Eliminar" size="small" text severity="danger" @click="deletePlot(p)" />
          </div>
        </article>
      </SectionCard>
    </div>
  </div>

  <PromptDialog
    v-model="promptValue" :visible="!!prompt" :title="prompt?.title ?? ''" :label="prompt?.label ?? ''"
    :ok-text="prompt?.okText" @confirm="promptOk" @cancel="prompt = null"
  />
</template>

<style scoped>
.hint { margin: 0 0 10px; }
.editing { margin-bottom: 10px; }
.ml { margin-left: 10px; }

.pick {
  display: block; width: 100%; text-align: left; background: var(--surface); cursor: pointer;
  border: 1px solid var(--border); border-radius: 12px; padding: 10px 12px; font: inherit; color: inherit;
  transition: border-color .15s, background .15s;
}
.pick + .pick { margin-top: 8px; }
.pick:hover { background: #f7f9f5; }
.pick.on { border-color: var(--leaf); background: #f2f8f2; }
.pick-top { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
.pick-actions { display: flex; gap: 2px; margin: 4px -8px -6px; flex-wrap: wrap; }

.plot { border: 1px solid var(--border); border-radius: 12px; padding: 12px; background: #fbfcfa; }
.plot + .plot { margin-top: 10px; }
.plot.on { border-color: var(--leaf); background: #f2f8f2; }
.plot-top { display: flex; align-items: center; gap: 9px; }
.dot { width: 9px; height: 9px; border-radius: 50%; background: var(--warn); flex-shrink: 0; }
.dot.active { background: var(--ok); }
.cycles { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; margin: 10px 0 4px; }
.cycle-chip {
  display: inline-flex; align-items: center; gap: 6px; background: var(--surface); cursor: pointer;
  border: 1px solid var(--border); border-radius: 999px; padding: 3px 10px 3px 4px; font: inherit; font-size: 12.5px;
}
.cycle-chip:hover { border-color: var(--leaf); }
.plot-actions { display: flex; gap: 2px; margin: 0 -8px -6px; flex-wrap: wrap; }
</style>
