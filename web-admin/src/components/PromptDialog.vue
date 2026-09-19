<script setup lang="ts">
import Dialog from 'primevue/dialog'
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'

const model = defineModel<string>({ default: '' })
defineProps<{ visible: boolean; title: string; label: string; okText?: string }>()
const emit = defineEmits<{ confirm: []; cancel: [] }>()
</script>

<template>
  <Dialog
    :visible="visible" modal :draggable="false" :header="title" :style="{ width: '24rem' }"
    @update:visible="emit('cancel')"
  >
    <label class="field">
      <span>{{ label }}</span>
      <InputText v-model="model" autofocus @keyup.enter="emit('confirm')" />
    </label>
    <template #footer>
      <Button label="Cancelar" severity="secondary" text @click="emit('cancel')" />
      <Button :label="okText ?? 'Guardar'" @click="emit('confirm')" />
    </template>
  </Dialog>
</template>
