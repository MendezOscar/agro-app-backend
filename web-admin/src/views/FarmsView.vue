<script setup lang="ts">
import { onMounted, ref, shallowRef } from 'vue'
import { useRouter } from 'vue-router'
import mapboxgl from 'mapbox-gl'
import MapboxDraw from '@mapbox/mapbox-gl-draw'
import { farmsApi, cyclesApi, type Farm, type Plot, type Cycle } from '../api/resources'

const token = import.meta.env.VITE_MAPBOX_TOKEN as string
const router = useRouter()

const farms = ref<Farm[]>([])
const selectedFarm = ref<Farm | null>(null)
const plots = ref<Plot[]>([])
const cyclesByPlot = ref<Record<string, Cycle[]>>({})
const drawMode = ref<'farm' | 'plot'>('farm')

const mapEl = ref<HTMLDivElement | null>(null)
const map = shallowRef<mapboxgl.Map | null>(null)
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const draw = shallowRef<any>(null)

onMounted(async () => {
  farms.value = await farmsApi.list()
  if (token) initMap()
})

function initMap() {
  mapboxgl.accessToken = token
  const m = new mapboxgl.Map({
    container: mapEl.value!,
    style: 'mapbox://styles/mapbox/satellite-streets-v12',
    center: [-75.595, 6.205],
    zoom: 12,
  })
  const d = new MapboxDraw({ displayControlsDefault: false, controls: { polygon: true, trash: true } })
  m.addControl(d)
  m.on('draw.create', onDraw)
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
  if (m.getSource(id)) return
  m.addSource(id, {
    type: 'geojson',
    data: { type: 'Feature', properties: {}, geometry: { type: 'Polygon', coordinates: [ring] } },
  })
  m.addLayer({ id: `${id}-fill`, type: 'fill', source: id, paint: { 'fill-color': color, 'fill-opacity': 0.3 } })
  m.addLayer({ id: `${id}-line`, type: 'line', source: id, paint: { 'line-color': color, 'line-width': 2 } })
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
        Configura <code>VITE_MAPBOX_TOKEN</code> en <code>.env</code> para habilitar el mapa.
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
        <div ref="mapEl" class="map"></div>
      </template>
    </div>

    <div class="card" style="flex:1;min-width:280px">
      <h3>Listado</h3>
      <ul style="list-style:none;padding:0">
        <li v-for="f in farms" :key="f.id" style="margin-bottom:6px">
          <a href="#" @click.prevent="selectFarm(f)"><strong>{{ f.name }}</strong></a>
          <span class="muted"> · {{ f.areaHa.toFixed(2) }} ha</span>
        </li>
      </ul>

      <template v-if="selectedFarm">
        <h4>Lotes de {{ selectedFarm.name }}</h4>
        <div v-for="p in plots" :key="p.id" style="margin-bottom:10px">
          <strong>{{ p.name }}</strong> <span class="muted">{{ p.areaHa.toFixed(2) }} ha</span>
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
