<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const email = ref('owner@demo.com')
const password = ref('Demo1234!')
const error = ref('')
const loading = ref(false)
const auth = useAuthStore()
const router = useRouter()

async function submit() {
  loading.value = true
  error.value = ''
  try {
    await auth.login(email.value.trim(), password.value)
    router.push({ name: 'farms' })
  } catch {
    error.value = 'Credenciales inválidas.'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="login-wrap">
    <form class="card" style="width:320px" @submit.prevent="submit">
      <h2 style="margin-top:0">🌱 AgroApp</h2>
      <p class="muted">Panel administrativo</p>
      <label>Email</label>
      <input v-model="email" type="email" style="width:100%;margin:4px 0 12px;padding:8px" />
      <label>Contraseña</label>
      <input v-model="password" type="password" style="width:100%;margin:4px 0 12px;padding:8px" />
      <p v-if="error" style="color:#dc2626">{{ error }}</p>
      <button :disabled="loading" style="width:100%;padding:10px;background:#16a34a;color:#fff;border:none;border-radius:8px;cursor:pointer">
        {{ loading ? 'Ingresando…' : 'Iniciar sesión' }}
      </button>
    </form>
  </div>
</template>
