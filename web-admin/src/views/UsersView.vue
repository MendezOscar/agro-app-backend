<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { usersApi, type OrgUser } from '../api/resources'
import Modal from '../components/Modal.vue'
import { confirmDialog } from '../composables/dialog'

const roleLabels = ['Dueño', 'Ingeniero agrónomo', 'Técnico de campo', 'Jornalero']
const users = ref<OrgUser[]>([])
const form = ref({ fullName: '', email: '', password: '', role: 2 })
const error = ref('')

onMounted(load)
async function load() {
  users.value = await usersApi.list()
}

function apiError(e: any, fallback: string) {
  const data = e?.response?.data
  if (data?.message) return data.message
  if (Array.isArray(data?.errors)) return data.errors.join(' ')
  return fallback
}

async function create() {
  error.value = ''
  try {
    await usersApi.create(form.value)
    form.value = { fullName: '', email: '', password: '', role: 2 }
    await load()
  } catch (e: any) {
    error.value = apiError(e, 'No se pudo crear el usuario.')
  }
}

// Edición (modal)
const editing = ref<OrgUser | null>(null)
const editForm = ref({ fullName: '', role: 2 })
const editError = ref('')
function edit(u: OrgUser) {
  editing.value = u
  editForm.value = { fullName: u.fullName, role: u.role }
  editError.value = ''
}
async function saveEdit() {
  if (!editing.value || !editForm.value.fullName.trim()) return
  editError.value = ''
  try {
    await usersApi.update(editing.value.id, { fullName: editForm.value.fullName.trim(), role: editForm.value.role })
    editing.value = null
    await load()
  } catch (e: any) {
    editError.value = apiError(e, 'No se pudo editar.')
  }
}

async function remove(u: OrgUser) {
  if (!(await confirmDialog({ title: 'Eliminar usuario', message: `¿Eliminar a ${u.fullName}? Esta acción no se puede deshacer.`, danger: true, okText: 'Eliminar' }))) return
  try {
    await usersApi.remove(u.id)
    await load()
  } catch (e: any) {
    error.value = apiError(e, 'No se pudo eliminar.')
  }
}
</script>

<template>
  <h2>Equipo</h2>
  <div class="row">
    <div class="card" style="flex:2;min-width:360px">
      <table>
        <thead><tr><th>Nombre</th><th>Email</th><th>Rol</th><th></th></tr></thead>
        <tbody>
          <tr v-for="u in users" :key="u.id">
            <td>{{ u.fullName }}</td>
            <td>{{ u.email }}</td>
            <td>{{ roleLabels[u.role] }}</td>
            <td style="white-space:nowrap;text-align:right">
              <button v-if="u.role !== 0" @click="edit(u)" class="btn-ghost" style="padding:4px 8px;margin-right:6px">Editar</button>
              <button v-if="u.role !== 0" @click="remove(u)" class="btn-ghost" style="padding:4px 8px;color:#dc2626">Eliminar</button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div class="card" style="flex:1;min-width:280px">
      <h3>Invitar agrónomo</h3>
      <form @submit.prevent="create">
        <input v-model="form.fullName" placeholder="Nombre completo" style="width:100%;margin:4px 0;padding:8px" />
        <input v-model="form.email" type="email" placeholder="Email" style="width:100%;margin:4px 0;padding:8px" />
        <input v-model="form.password" type="password" placeholder="Contraseña" style="width:100%;margin:4px 0;padding:8px" />
        <p class="muted" style="font-size:12px;margin:2px 0 6px">Mín. 8, con mayúscula, minúscula, número y símbolo.</p>
        <select v-model.number="form.role" style="width:100%;margin:4px 0;padding:8px">
          <option :value="1">Ingeniero agrónomo</option>
          <option :value="2">Técnico de campo</option>
          <option :value="3">Jornalero</option>
        </select>
        <p v-if="error" style="color:#dc2626">{{ error }}</p>
        <button style="width:100%;padding:10px;background:#16a34a;color:#fff;border:none;border-radius:8px;cursor:pointer">Crear</button>
      </form>
    </div>
  </div>

  <Modal v-if="editing" title="Editar usuario" @close="editing = null">
    <label class="fld">Nombre completo
      <input v-model="editForm.fullName" />
    </label>
    <label class="fld">Rol
      <select v-model.number="editForm.role">
        <option :value="1">Ingeniero agrónomo</option>
        <option :value="2">Técnico de campo</option>
        <option :value="3">Jornalero</option>
      </select>
    </label>
    <p v-if="editError" style="color:#dc2626;margin:10px 0 0">{{ editError }}</p>
    <template #actions>
      <button class="btn-ghost" @click="editing = null">Cancelar</button>
      <button class="btn" @click="saveEdit">Guardar</button>
    </template>
  </Modal>
</template>

<style scoped>
.fld { display:block; font-size:13px; font-weight:600; color:#444; margin:10px 0 0 }
.fld input, .fld select { width:100%; margin:4px 0 0; padding:8px; font-weight:400 }
</style>
