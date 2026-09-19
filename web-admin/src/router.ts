import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from './stores/auth'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/login', name: 'login', component: () => import('./views/LoginView.vue') },
    {
      path: '/',
      component: () => import('./views/AppLayout.vue'),
      meta: { auth: true },
      children: [
        { path: '', redirect: '/inicio' },
        { path: 'inicio', name: 'dashboard', meta: { title: 'Inicio' }, component: () => import('./views/DashboardView.vue') },
        { path: 'farms', name: 'farms', meta: { title: 'Fincas y lotes' }, component: () => import('./views/FarmsView.vue') },
        { path: 'inputs', name: 'inputs', meta: { title: 'Insumos' }, component: () => import('./views/InputsView.vue') },
        { path: 'plots/:id/analyses', name: 'analyses', meta: { title: 'Análisis del lote' }, component: () => import('./views/PlotAnalysesView.vue') },
        { path: 'cycles/:id', name: 'cycle', meta: { title: 'Ciclo de cultivo' }, component: () => import('./views/CycleView.vue') },
        { path: 'harvest-templates', name: 'harvest-templates', meta: { title: 'Proceso de cosecha' }, component: () => import('./views/HarvestTemplatesView.vue') },
        { path: 'users', name: 'users', meta: { title: 'Equipo' }, component: () => import('./views/UsersView.vue') },
      ],
    },
  ],
})

router.beforeEach((to) => {
  const auth = useAuthStore()
  if (to.meta.auth && !auth.isAuthenticated) return { name: 'login' }
  if (to.name === 'login' && auth.isAuthenticated) return { name: 'dashboard' }
})

export default router
