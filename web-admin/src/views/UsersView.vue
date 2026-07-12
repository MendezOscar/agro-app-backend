<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { usersApi, type OrgUser } from '../api/resources'

const roleLabels = ['Dueño', 'Gerente agrónomo', 'Agrónomo']
const users = ref<OrgUser[]>([])
const form = ref({ fullName: '', email: '', password: '', role: 2 })
const error = ref('')

onMounted(load)
async function load() {
  users.value = await usersApi.list()
}

async function create() {
  error.value = ''
  try {
    await usersApi.create(form.value)
    form.value = { fullName: '', email: '', password: '', role: 2 }
    await load()
  } catch {
    error.value = 'No se pudo crear el usuario (¿email repetido o contraseña corta?).'
  }
}
</script>

<template>
  <h2>Equipo</h2>
  <div class="row">
    <div class="card" style="flex:2;min-width:360px">
      <table>
        <thead><tr><th>Nombre</th><th>Email</th><th>Rol</th></tr></thead>
        <tbody>
          <tr v-for="u in users" :key="u.id">
            <td>{{ u.fullName }}</td>
            <td>{{ u.email }}</td>
            <td>{{ roleLabels[u.role] }}</td>
          </tr>
        </tbody>
      </table>
    </div>

    <div class="card" style="flex:1;min-width:280px">
      <h3>Invitar agrónomo</h3>
      <form @submit.prevent="create">
        <input v-model="form.fullName" placeholder="Nombre completo" style="width:100%;margin:4px 0;padding:8px" />
        <input v-model="form.email" type="email" placeholder="Email" style="width:100%;margin:4px 0;padding:8px" />
        <input v-model="form.password" type="password" placeholder="Contraseña (mín. 8)" style="width:100%;margin:4px 0;padding:8px" />
        <select v-model.number="form.role" style="width:100%;margin:4px 0;padding:8px">
          <option :value="1">Gerente agrónomo</option>
          <option :value="2">Agrónomo</option>
        </select>
        <p v-if="error" style="color:#dc2626">{{ error }}</p>
        <button style="width:100%;padding:10px;background:#16a34a;color:#fff;border:none;border-radius:8px;cursor:pointer">Crear</button>
      </form>
    </div>
  </div>
</template>
