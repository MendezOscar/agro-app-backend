<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Password from 'primevue/password'
import Message from 'primevue/message'
import { useAuthStore } from '../stores/auth'

const email = ref('owner@naara.com')
const password = ref('Naara2026*')
const error = ref('')
const loading = ref(false)
const auth = useAuthStore()
const router = useRouter()

async function submit() {
  if (!email.value.trim() || !password.value) { error.value = 'Ingresa tu correo y contraseña.'; return }
  loading.value = true
  error.value = ''
  try {
    await auth.login(email.value.trim(), password.value)
    router.push({ name: 'dashboard' })
  } catch (e: any) {
    const status = e?.response?.status
    if (status === 401) error.value = 'Credenciales inválidas. Revisa tu correo y contraseña.'
    else if (e?.code === 'ECONNABORTED' || e?.message === 'Network Error' || !status)
      error.value = 'Sin conexión o el servidor está iniciando (puede tardar ~30 s). Reintenta.'
    else error.value = `Error del servidor (${status}). Intenta más tarde.`
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="login">
    <!-- Panel de marca -->
    <aside class="brand-side">
      <img src="/brand/mark-mono-light.svg" alt="" class="mark" />
      <h1>Gestiona tu finca<br />de principio a fin</h1>
      <p>Ciclos por etapas, costos en lempiras, clima y monitoreo del cultivo en un solo panel.</p>
      <ul>
        <li><i class="pi pi-check-circle" /> Las 8 etapas del proceso agronómico</li>
        <li><i class="pi pi-check-circle" /> Costos e insumos con alertas de stock</li>
        <li><i class="pi pi-check-circle" /> Mapa de lotes y observaciones con IA</li>
      </ul>
    </aside>

    <!-- Formulario -->
    <main class="form-side">
      <form class="box" @submit.prevent="submit">
        <img src="/brand/mark-color.svg" alt="AgroApp" class="logo" />
        <h2>Bienvenido de vuelta</h2>
        <p class="muted sub">Entra al panel administrativo de AgroApp.</p>

        <label class="field">
          <span>Correo</span>
          <InputText v-model="email" type="email" autocomplete="username" placeholder="tu@finca.com" />
        </label>
        <label class="field">
          <span>Contraseña</span>
          <Password v-model="password" :feedback="false" toggle-mask input-class="w-full" fluid />
        </label>

        <Message v-if="error" severity="error" :closable="false" class="msg">{{ error }}</Message>

        <Button type="submit" :loading="loading" label="Iniciar sesión" class="submit" />
        <p v-if="loading" class="tiny center">Si el servidor estaba inactivo puede tardar unos segundos.</p>
      </form>
    </main>
  </div>
</template>

<style scoped>
.login { display: grid; grid-template-columns: 1.05fr 1fr; min-height: 100vh; }
.brand-side {
  background: linear-gradient(155deg, #24632f 0%, #143d1d 100%); color: #fff;
  padding: 54px 52px; display: flex; flex-direction: column; justify-content: center;
}
.brand-side .mark { width: 52px; margin-bottom: 26px; }
.brand-side h1 { font-size: 36px; font-weight: 800; line-height: 1.15; }
.brand-side p { color: #c7dfc9; margin: 16px 0 28px; max-width: 30ch; line-height: 1.55; }
.brand-side ul { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 12px; }
.brand-side li { display: flex; align-items: center; gap: 10px; color: #e3f0e3; font-size: 14.5px; }
.brand-side li i { color: var(--leaf-light); }

.form-side { display: grid; place-items: center; padding: 32px; background: var(--bg); }
.box { width: 100%; max-width: 372px; display: flex; flex-direction: column; gap: 14px; }
.logo { height: 58px; align-self: flex-start; }
.box h2 { font-size: 23px; font-weight: 800; }
.sub { margin: -8px 0 6px; }
.msg { margin: 0; }
.submit { margin-top: 4px; }
.center { text-align: center; }

@media (max-width: 860px) {
  .login { grid-template-columns: 1fr; }
  .brand-side { display: none; }
}
</style>
