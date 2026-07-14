<script setup lang="ts">
import { onMounted, ref, shallowRef } from 'vue'
import { useRouter } from 'vue-router'
import maplibregl from 'maplibre-gl'
// @ts-expect-error: sin tipos; MapboxDraw es compatible con MapLibre en runtime
import MapboxDraw from '@mapbox/mapbox-gl-draw'
import { farmsApi, cyclesApi, type Farm, type Plot, type Cycle } from '../api/resources'

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

onMounted(async () => {
  farms.value = await farmsApi.list()
  if (token) initMap()
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
  m.on('load', () => renderFarms())
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
  const m = map.value!
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

async function renameFarm(f: Farm) {
  const name = prompt('Nuevo nombre de la finca', f.name)
  if (!name || name === f.name) return
  await farmsApi.update(f.id, { name, boundary: f.boundary, location: f.location })
  farms.value = await farmsApi.list()
}

async function deleteFarm(f: Farm) {
  if (!confirm(`¿Eliminar la finca "${f.name}" y todo su contenido?`)) return
  await farmsApi.remove(f.id)
  removePolygonLayer(`farm-${f.id}`)
  if (selectedFarm.value?.id === f.id) selectedFarm.value = null
  farms.value = await farmsApi.list()
}

async function deletePlot(p: Plot) {
  if (!confirm(`¿Eliminar el lote "${p.name}"?`)) return
  await farmsApi.removePlot(p.id)
  removePolygonLayer(`plot-${p.id}`)
  if (selectedFarm.value) await selectFarm(selectedFarm.value)
}

async function onDraw(e: { features: Array<{ geometry: { coordinates: number[][][] } }> }) {
  const ring = e.features[0].geometry.coordinates[0]
  const name = prompt(drawMode.value === 'farm' ? 'Nombre de la finca' : 'Nombre del lote')
  draw.value?.deleteAll()
  if (!name) return

  if (drawMode.value === 'farm') {
    await farmsApi.create({ name, boundary: ring, location: ring[0] })
    farms.value = await farmsApi.list()
    renderFarms()
  } else if (selectedFarm.value) {
    await farmsApi.createPlot(selectedFarm.value.id, { name, boundary: ring })
    await selectFarm(selectedFarm.value)
  } else {
    alert('Selecciona primero una finca para dibujar un lote.')
  }
}

async function selectFarm(f: Farm) {
  selectedFarm.value = f
  plots.value = await farmsApi.plots(f.id)
  for (const p of plots.value) {
    cyclesByPlot.value[p.id] = await cyclesApi.byPlot(p.id)
    if (p.boundary) addPolygonLayer(`plot-${p.id}`, p.boundary, '#f59e0b')
  }
  if (f.location && map.value) map.value.flyTo({ center: f.location as [number, number], zoom: 14 })
}

async function newCycle(plot: Plot) {
  const crop = prompt('Cultivo (ej. Maíz)')
  if (!crop) return
  await cyclesApi.create({ plotId: plot.id, crop })
  cyclesByPlot.value[plot.id] = await cyclesApi.byPlot(plot.id)
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
          <span class="muted"> — usa la herramienta de polígono del mapa.</span>
        </div>
        <div v-if="editing" style="margin-bottom:8px;padding:8px;background:#fef3c7;border-radius:6px">
          Editando <strong>{{ editing.name }}</strong>: arrastra los vértices en el mapa.
          <button @click="finishEdit" style="margin-left:8px;padding:4px 10px;background:#16a34a;color:#fff;border:none;border-radius:6px;cursor:pointer">Terminar</button>
        </div>
        <div ref="mapEl" class="map"></div>
      </template>
    </div>

    <div class="card" style="flex:1;min-width:280px">
      <h3>Listado</h3>
      <ul style="list-style:none;padding:0">
        <li v-for="f in farms" :key="f.id" style="margin-bottom:6px">
          <a href="#" @click.prevent="selectFarm(f)"><strong>{{ f.name }}</strong></a>
          <span class="muted"> · {{ f.areaHa.toFixed(2) }} ha</span>
          <div style="font-size:0.82em;margin-top:2px">
            <a href="#" @click.prevent="editOnMap('farm', f.id, f.name, f.boundary)">Editar mapa</a> ·
            <a href="#" @click.prevent="renameFarm(f)">Renombrar</a> ·
            <a href="#" style="color:#dc2626" @click.prevent="deleteFarm(f)">Eliminar</a>
          </div>
        </li>
      </ul>

      <template v-if="selectedFarm">
        <h4>Lotes de {{ selectedFarm.name }}</h4>
        <div v-for="p in plots" :key="p.id" style="margin-bottom:10px">
          <strong>{{ p.name }}</strong> <span class="muted">{{ p.areaHa.toFixed(2) }} ha</span>
          <a href="#" style="margin-left:8px;font-size:0.85em"
            @click.prevent="router.push({ name: 'analyses', params: { id: p.id }, query: { name: p.name } })">Análisis</a>
          <div style="font-size:0.82em;margin-top:2px">
            <a href="#" @click.prevent="editOnMap('plot', p.id, p.name, p.boundary)">Editar mapa</a> ·
            <a href="#" style="color:#dc2626" @click.prevent="deletePlot(p)">Eliminar</a>
          </div>
          <div style="margin:4px 0">
            <span
              v-for="c in cyclesByPlot[p.id] || []"
              :key="c.id"
              style="display:inline-block;margin:2px;padding:2px 8px;background:#dcfce7;border-radius:6px;cursor:pointer"
              @click="router.push({ name: 'cycle', params: { id: c.id } })"
            >{{ c.crop }}</span>
            <button @click="newCycle(p)" style="margin-left:6px">+ ciclo</button>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
