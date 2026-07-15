<script setup lang="ts">
import { RouterView, useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const auth = useAuthStore()
const router = useRouter()

function logout() {
  auth.logout()
  router.push({ name: 'login' })
}
</script>

<template>
  <div class="layout">
    <nav class="sidebar">
      <div class="brand">
        <img src="/brand/mark-mono-light.svg" alt="AgroApp" />
        <span>AgroApp</span>
      </div>
      <RouterLink to="/inicio">📊 Inicio</RouterLink>
      <RouterLink to="/farms">🌱 Fincas</RouterLink>
      <RouterLink to="/inputs">📦 Insumos</RouterLink>
      <RouterLink v-if="auth.canManageUsers" to="/users">👥 Equipo</RouterLink>
      <div class="spacer" />
      <div class="muted" style="color:#bbf7d0">{{ auth.fullName }}<br />({{ auth.role }})</div>
      <a href="#" @click.prevent="logout">Cerrar sesión</a>
    </nav>
    <main class="content">
      <RouterView />
    </main>
  </div>
</template>
