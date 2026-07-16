<script setup lang="ts">
import { onMounted, ref, shallowRef } from 'vue'
import { useRouter } from 'vue-router'
import maplibregl from 'maplibre-gl'
// @ts-expect-error: sin tipos; MapboxDraw es compatible con MapLibre en runtime
import MapboxDraw from '@mapbox/mapbox-gl-draw'
import { farmsApi, cyclesApi, type Farm, type Plot, type Cycle } from '../api/resources'
import Modal from '../components/Modal.vue'
import { confirmDialog, alertDialog } from '../composables/dialog'

// Modal genérico de texto (reemplaza prompt del navegador)
const promptState = ref<null | { title: string; label: string; value: string; okText: string; onOk: (v: string) => void | Promise<void> }>(null)
function openPrompt(title: string, label: string, value: string, onOk: (v: string) => void | Promise<void>, okText = 'Guardar') {
  promptState.value = { title, label, value, okText, onOk }
}
async function promptOk() {
  const s = promptState.value
  if (!s) return
  const v = s.value.trim()
  promptState.value = null
  if (v) await s.onOk(v)
}

const token = import.meta.env.VITE_MAPTILER_KEY as string
const router = useRouter()

const farms = ref<Farm[]>([])
const selectedFarm = ref<Farm | null>(null)
const plots = ref<Plot[]>([])
const cyclesByPlot = ref<Record<string, Cycle[]>>({})
const drawMode = ref<'farm' | 'plot'>('farm')
const editing = ref<{ kind: 'farm' | 'plot'; id: string; name: string } | null>(null)

const mapEl = ref<HTMLDivElement | null>(null)
const map = shallowRef<maplibregl.Map | null>(null)
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const draw = shallowRef<any>(null)

const cycleStatusLabels = ['Planificada', 'Activa', 'Cosechada', 'Cerrada']
const cycleStatusColor = (s: number) => ['#94a3b8', '#16a34a', '#f59e0b', '#334155'][s]
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
  openPrompt('Nuevo ciclo', 'Cultivo (ej. Maíz)', '', async (crop) => {
    await cyclesApi.create({ plotId: plot.id, crop })
    cyclesByPlot.value[plot.id] = await cyclesApi.byPlot(plot.id)
  }, 'Crear')
}
</script>

<template>
  <h2>Fincas</h2>
  <div class="row">
    <div class="card" style="flex:2;min-width:420px">
      <div v-if="!token" class="muted">
        Configura <code>VITE_MAPTILER_KEY</code> en <code>.env</code> para habilitar el mapa.
      </div>
      <template v-else>
        <div style="margin-bottom:8px">
          <label>Dibujar: </label>
          <select v-model="drawMode">
            <option value="farm">Finca</option>
            <option value="plot">Lote (en finca seleccionada)</option>
          </select>
          <button @click="startDraw" style="margin-left:8px;padding:6px 12px;background:#16a34a;color:#fff;border:none;border-radius:6px;cursor:pointer">
            ✏️ Dibujar en el mapa
          </button>
          <span class="muted"> — traza el polígono y haz doble clic para cerrar.</span>
        </div>
        <div v-if="editing" style="margin-bottom:8px;padding:8px;background:#fef3c7;border-radius:6px">
          Editando <strong>{{ editing.name }}</strong>: arrastra los vértices en el mapa.
          <button @click="finishEdit" style="margin-left:8px;padding:4px 10px;background:#16a34a;color:#fff;border:none;border-radius:6px;cursor:pointer">Terminar</button>
        </div>
        <div ref="mapEl" class="map"></div>
      </template>
    </div>

    <div class="card" style="flex:1;min-width:300px">
      <h3 style="margin-top:0">Fincas</h3>
      <div v-for="f in farms" :key="f.id"
        @click="selectFarm(f)"
        :style="{
          padding:'10px 12px', borderRadius:'10px', marginBottom:'6px', cursor:'pointer',
          border: selectedFarm?.id === f.id ? '2px solid var(--leaf)' : '1px solid var(--border)',
          background: selectedFarm?.id === f.id ? '#f0fdf4' : '#fff',
        }">
        <div style="display:flex;align-items:center;gap:6px">
          <strong style="flex:1">{{ f.name }}</strong>
          <span class="muted">{{ f.areaHa.toFixed(1) }} ha</span>
        </div>
        <div style="font-size:0.82em;margin-top:3px">
          <a href="#" @click.stop.prevent="editOnMap('farm', f.id, f.name, f.boundary)">Editar mapa</a> ·
          <a href="#" @click.stop.prevent="renameFarm(f)">Renombrar</a> ·
          <a href="#" style="color:#dc2626" @click.stop.prevent="deleteFarm(f)">Eliminar</a>
        </div>
      </div>

      <template v-if="selectedFarm">
        <h4 style="margin:18px 0 8px">Lotes de {{ selectedFarm.name }}</h4>
        <p v-if="!plots.length" class="muted">Sin lotes. Dibuja uno en el mapa.</p>
        <div v-for="p in plots" :key="p.id"
          :style="{
            padding:'12px', borderRadius:'12px', marginBottom:'10px',
            border: plotActiveCycle(p.id) ? '2px solid var(--leaf)' : '1px solid var(--border)',
            background: plotActiveCycle(p.id) ? '#f0fdf4' : '#fafbf9',
          }">
          <div style="display:flex;align-items:center;gap:8px">
            <span :style="{ width:'10px', height:'10px', borderRadius:'50%', background: plotActiveCycle(p.id) ? '#16a34a' : '#f59e0b' }"></span>
            <strong style="flex:1">{{ p.name }}</strong>
            <span class="muted">{{ p.areaHa.toFixed(2) }} ha</span>
          </div>
          <div v-if="plotActiveCycle(p.id)" style="margin-top:4px">
            <span class="chip" style="background:#dcfce7;color:#166534">● Ciclo activo: {{ plotActiveCycle(p.id)!.crop }}</span>
          </div>

          <!-- Ciclos con estado y enlace directo -->
          <div style="display:flex;flex-wrap:wrap;gap:6px;margin:8px 0">
            <a v-for="c in cyclesByPlot[p.id] || []" :key="c.id" href="#"
              @click.prevent="router.push({ name: 'cycle', params: { id: c.id } })"
              class="chip"
              :style="{ background: cycleStatusColor(c.status) + '22', color: cycleStatusColor(c.status), textDecoration:'none' }">
              🌾 {{ c.crop }} · {{ cycleStatusLabels[c.status] }}
            </a>
            <button class="btn btn-sm btn-ghost" @click="newCycle(p)">+ ciclo</button>
          </div>

          <div style="font-size:0.82em">
            <a href="#" @click.prevent="router.push({ name: 'analyses', params: { id: p.id }, query: { name: p.name } })">Análisis</a> ·
            <a href="#" @click.prevent="editOnMap('plot', p.id, p.name, p.boundary)">Editar mapa</a> ·
            <a href="#" style="color:#dc2626" @click.prevent="deletePlot(p)">Eliminar</a>
          </div>
        </div>
      </template>
    </div>
  </div>

  <Modal v-if="promptState" :title="promptState.title" @close="promptState = null">
    <label style="display:block;font-size:13px;font-weight:600;color:#444">{{ promptState.label }}
      <input v-model="promptState.value" style="width:100%;margin:4px 0 0;padding:8px" @keyup.enter="promptOk" />
    </label>
    <template #actions>
      <button class="btn-ghost" @click="promptState = null">Cancelar</button>
      <button class="btn" @click="promptOk">{{ promptState.okText }}</button>
    </template>
  </Modal>
</template>
