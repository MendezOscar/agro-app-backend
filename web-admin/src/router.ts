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
        { path: '', redirect: '/farms' },
        { path: 'farms', name: 'farms', component: () => import('./views/FarmsView.vue') },
        { path: 'inputs', name: 'inputs', component: () => import('./views/InputsView.vue') },
        { path: 'plots/:id/analyses', name: 'analyses', component: () => import('./views/PlotAnalysesView.vue') },
        { path: 'cycles/:id', name: 'cycle', component: () => import('./views/CycleView.vue') },
        { path: 'users', name: 'users', component: () => import('./views/UsersView.vue') },
      ],
    },
  ],
})

router.beforeEach((to) => {
  const auth = useAuthStore()
  if (to.meta.auth && !auth.isAuthenticated) return { name: 'login' }
  if (to.name === 'login' && auth.isAuthenticated) return { name: 'farms' }
})

export default router
