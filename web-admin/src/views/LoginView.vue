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
    <form class="card" style="width:360px;padding:32px" @submit.prevent="submit">
      <div style="text-align:center;margin-bottom:20px">
        <img src="/brand/mark-color.svg" alt="AgroApp" style="height:76px" />
        <h2 style="margin:14px 0 2px">AgroApp</h2>
        <p class="muted" style="margin:0">Panel administrativo</p>
      </div>
      <label>Email</label>
      <input v-model="email" type="email" style="width:100%;margin:4px 0 14px" />
      <label>Contraseña</label>
      <input v-model="password" type="password" style="width:100%;margin:4px 0 14px" />
      <p v-if="error" style="color:#dc2626;font-size:14px">{{ error }}</p>
      <button class="btn" :disabled="loading" style="width:100%">
        {{ loading ? 'Ingresando…' : 'Iniciar sesión' }}
      </button>
    </form>
  </div>
</template>
