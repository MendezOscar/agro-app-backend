<script setup lang="ts">
import { computed, ref } from 'vue'
import { RouterView, useRoute, useRouter } from 'vue-router'
import Drawer from 'primevue/drawer'
import Menu from 'primevue/menu'
import Avatar from 'primevue/avatar'
import Button from 'primevue/button'
import Toast from 'primevue/toast'
import { useAuthStore } from '../stores/auth'
import ConfirmHost from '../components/ConfirmHost.vue'

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const mobileNav = ref(false)
const userMenu = ref<InstanceType<typeof Menu> | null>(null)

const roleLabels: Record<string, string> = {
  Owner: 'Dueño',
  AgronomistManager: 'Ingeniero agrónomo',
  AgronomistWorker: 'Técnico de campo',
  Laborer: 'Jornalero',
}

const links = computed(() => [
  { to: '/inicio', icon: 'pi-home', label: 'Inicio' },
  { to: '/farms', icon: 'pi-map', label: 'Fincas y lotes' },
  { to: '/inputs', icon: 'pi-box', label: 'Insumos' },
  { to: '/harvest-templates', icon: 'pi-sliders-h', label: 'Proceso de cosecha' },
  ...(auth.canManageUsers ? [{ to: '/users', icon: 'pi-users', label: 'Equipo' }] : []),
])

const pageTitle = computed(() => (route.meta.title as string) ?? 'AgroApp')
const initials = computed(() =>
  (auth.fullName ?? '?').split(' ').filter(Boolean).slice(0, 2).map((p) => p[0]!.toUpperCase()).join(''),
)

const userItems = [
  { label: 'Cerrar sesión', icon: 'pi pi-sign-out', command: () => { auth.logout(); router.push({ name: 'login' }) } },
]
</script>

<template>
  <div class="shell">
    <!-- Navegación fija (escritorio) -->
    <nav class="sidebar desktop-only">
      <div class="brand">
        <img src="/brand/mark-mono-light.svg" alt="" />
        <span>AgroApp</span>
      </div>
      <div class="nav-section">Operación</div>
      <RouterLink v-for="l in links" :key="l.to" :to="l.to" class="nav-link">
        <i :class="['pi', l.icon]" /> {{ l.label }}
      </RouterLink>
      <div class="spacer" />
      <div class="sidebar-user">
        <strong>{{ auth.fullName }}</strong>
        <span>{{ roleLabels[auth.role ?? ''] ?? auth.role }}</span>
      </div>
    </nav>

    <div class="main">
      <header class="topbar">
        <Button
          class="mobile-only" icon="pi pi-bars" text severity="secondary"
          aria-label="Menú" @click="mobileNav = true"
        />
        <h2 class="topbar-title">{{ pageTitle }}</h2>
        <span style="flex:1" />
        <button class="user-btn" @click="userMenu?.toggle($event)">
          <Avatar :label="initials" shape="circle" class="avatar" />
          <span class="desktop-only">{{ auth.fullName }}</span>
          <i class="pi pi-angle-down" />
        </button>
        <Menu ref="userMenu" :model="userItems" :popup="true" />
      </header>

      <main class="content">
        <RouterView />
      </main>
    </div>

    <!-- Navegación en móvil -->
    <Drawer v-model:visible="mobileNav" header="AgroApp" class="nav-drawer">
      <nav class="drawer-nav">
        <RouterLink v-for="l in links" :key="l.to" :to="l.to" class="drawer-link" @click="mobileNav = false">
          <i :class="['pi', l.icon]" /> {{ l.label }}
        </RouterLink>
      </nav>
    </Drawer>

    <ConfirmHost />
    <Toast position="bottom-right" />
  </div>
</template>

<style scoped>
.sidebar-user { padding: 12px; border-top: 1px solid rgba(255, 255, 255, .12); display: flex; flex-direction: column; }
.sidebar-user strong { color: #fff; font-size: 13.5px; }
.sidebar-user span { color: #a6c9a9; font-size: 12px; }
.topbar-title { font-size: 16px; font-weight: 700; }
.user-btn {
  display: flex; align-items: center; gap: 9px; background: none; border: none; cursor: pointer;
  font: inherit; font-size: 13.5px; font-weight: 600; color: var(--ink); padding: 5px 8px; border-radius: 10px;
}
.user-btn:hover { background: #eef1ec; }
.avatar { background: #eaf3ea; color: var(--leaf-dark); font-weight: 700; width: 32px; height: 32px; font-size: 13px; }
.drawer-nav { display: flex; flex-direction: column; gap: 4px; }
.drawer-link {
  display: flex; align-items: center; gap: 11px; padding: 11px 12px; border-radius: 10px;
  text-decoration: none; color: var(--ink); font-weight: 600; font-size: 14.5px;
}
.drawer-link.router-link-active { background: #eaf3ea; color: var(--leaf-dark); }
.mobile-only { display: none; }
@media (max-width: 900px) {
  .desktop-only { display: none !important; }
  .mobile-only { display: inline-flex; }
}
</style>
