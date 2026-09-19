<script setup lang="ts">
import { onMounted, ref } from 'vue'
import Button from 'primevue/button'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import Password from 'primevue/password'
import Select from 'primevue/select'
import Message from 'primevue/message'
import Tag from 'primevue/tag'
import Avatar from 'primevue/avatar'
import { usersApi, type OrgUser } from '../api/resources'
import { confirmDialog } from '../composables/dialog'
import PageHeader from '../components/PageHeader.vue'
import SectionCard from '../components/SectionCard.vue'
import EmptyState from '../components/EmptyState.vue'

const roleLabels = ['Dueño', 'Ingeniero agrónomo', 'Técnico de campo', 'Jornalero']
const roleSeverity = ['contrast', 'success', 'info', 'secondary'] as const
// El rol Dueño no se asigna desde aquí: lo crea el registro de la organización.
const roleOptions = [1, 2, 3].map((value) => ({ label: roleLabels[value], value }))

const users = ref<OrgUser[]>([])
const error = ref('')

onMounted(load)
async function load() {
  users.value = await usersApi.list()
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function apiError(e: any, fallback: string) {
  const data = e?.response?.data
  if (data?.message) return data.message
  if (Array.isArray(data?.errors)) return data.errors.join(' ')
  return fallback
}

// Alta
const createOpen = ref(false)
const form = ref({ fullName: '', email: '', password: '', role: 2 })
const createError = ref('')
function openCreate() {
  form.value = { fullName: '', email: '', password: '', role: 2 }
  createError.value = ''
  createOpen.value = true
}
async function create() {
  createError.value = ''
  try {
    await usersApi.create(form.value)
    createOpen.value = false
    await load()
  } catch (e) {
    createError.value = apiError(e, 'No se pudo crear el usuario.')
  }
}

// Edición
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
  } catch (e) {
    editError.value = apiError(e, 'No se pudo editar.')
  }
}

async function remove(u: OrgUser) {
  if (!(await confirmDialog({ title: 'Eliminar usuario', message: `¿Eliminar a ${u.fullName}? Esta acción no se puede deshacer.`, danger: true, okText: 'Eliminar' }))) return
  try {
    await usersApi.remove(u.id)
    await load()
  } catch (e) {
    error.value = apiError(e, 'No se pudo eliminar.')
  }
}

const initials = (name: string) =>
  name.split(' ').filter(Boolean).slice(0, 2).map((p) => p[0]!.toUpperCase()).join('')
</script>

<template>
  <PageHeader title="Equipo" subtitle="Personas con acceso a la organización y su rol en la finca.">
    <template #actions>
      <Button label="Invitar persona" icon="pi pi-user-plus" @click="openCreate" />
    </template>
  </PageHeader>

  <Message v-if="error" severity="error" :closable="false" class="mb">{{ error }}</Message>

  <SectionCard title="Miembros" icon="pi-users" :subtitle="`${users.length} persona(s)`" flush>
    <DataTable :value="users" size="small">
      <template #empty><EmptyState icon="pi-users" text="Sin usuarios." /></template>
      <Column header="Nombre">
        <template #body="{ data }">
          <div class="person">
            <Avatar :label="initials(data.fullName)" shape="circle" class="av" />
            <strong>{{ data.fullName }}</strong>
          </div>
        </template>
      </Column>
      <Column field="email" header="Correo" />
      <Column header="Rol">
        <template #body="{ data }"><Tag :value="roleLabels[data.role]" :severity="roleSeverity[data.role]" /></template>
      </Column>
      <Column style="width:8rem">
        <template #body="{ data }">
          <div class="acts" v-if="data.role !== 0">
            <Button icon="pi pi-pencil" text rounded severity="secondary" v-tooltip.top="'Editar'" @click="edit(data)" />
            <Button icon="pi pi-trash" text rounded severity="danger" v-tooltip.top="'Eliminar'" @click="remove(data)" />
          </div>
        </template>
      </Column>
    </DataTable>
  </SectionCard>

  <Dialog v-model:visible="createOpen" modal :draggable="false" header="Invitar persona" :style="{ width: '28rem' }">
    <form class="dlg-form" @submit.prevent="create">
      <label class="field"><span>Nombre completo</span><InputText v-model="form.fullName" autofocus /></label>
      <label class="field"><span>Correo</span><InputText v-model="form.email" type="email" /></label>
      <label class="field">
        <span>Contraseña</span>
        <Password v-model="form.password" :feedback="false" toggle-mask fluid />
        <small class="tiny">Mínimo 8 caracteres, con mayúscula, minúscula, número y símbolo.</small>
      </label>
      <label class="field"><span>Rol</span>
        <Select v-model="form.role" :options="roleOptions" option-label="label" option-value="value" />
      </label>
      <Message v-if="createError" severity="error" :closable="false">{{ createError }}</Message>
    </form>
    <template #footer>
      <Button label="Cancelar" severity="secondary" text @click="createOpen = false" />
      <Button label="Crear" @click="create" />
    </template>
  </Dialog>

  <Dialog :visible="!!editing" modal :draggable="false" header="Editar usuario" :style="{ width: '26rem' }" @update:visible="editing = null">
    <form class="dlg-form" @submit.prevent="saveEdit">
      <label class="field"><span>Nombre completo</span><InputText v-model="editForm.fullName" autofocus /></label>
      <label class="field"><span>Rol</span>
        <Select v-model="editForm.role" :options="roleOptions" option-label="label" option-value="value" />
      </label>
      <Message v-if="editError" severity="error" :closable="false">{{ editError }}</Message>
    </form>
    <template #footer>
      <Button label="Cancelar" severity="secondary" text @click="editing = null" />
      <Button label="Guardar" @click="saveEdit" />
    </template>
  </Dialog>
</template>

<style scoped>
.mb { margin-bottom: 16px; }
.person { display: flex; align-items: center; gap: 10px; }
.av { background: #eaf3ea; color: var(--leaf-dark); font-weight: 700; width: 30px; height: 30px; font-size: 12px; }
.acts { display: flex; justify-content: flex-end; }
.dlg-form { display: flex; flex-direction: column; gap: 14px; }
</style>
