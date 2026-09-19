import { createApp } from 'vue'
import { createPinia } from 'pinia'
import PrimeVue from 'primevue/config'
import ToastService from 'primevue/toastservice'
import Tooltip from 'primevue/tooltip'
import 'primeicons/primeicons.css'
import 'maplibre-gl/dist/maplibre-gl.css'
import '@mapbox/mapbox-gl-draw/dist/mapbox-gl-draw.css'
import './style.css'

import { AgroPreset } from './theme'
import App from './App.vue'
import router from './router'

createApp(App)
  .use(createPinia())
  .use(router)
  // darkModeSelector desactiva el modo oscuro automático: la app es clara.
  .use(PrimeVue, { theme: { preset: AgroPreset, options: { darkModeSelector: '.app-dark' } }, ripple: false })
  .use(ToastService)
  .directive('tooltip', Tooltip)
  .mount('#app')
