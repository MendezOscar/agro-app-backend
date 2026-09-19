<script setup lang="ts">
import Dialog from 'primevue/dialog'
import Button from 'primevue/button'
import { dialogState } from '../composables/dialog'

function done(v: boolean) {
  dialogState.value?.resolve(v)
  dialogState.value = null
}
</script>

<template>
  <Dialog
    :visible="!!dialogState" modal :draggable="false" :style="{ width: '25rem' }"
    :header="dialogState?.title" @update:visible="done(false)"
  >
    <p class="msg">{{ dialogState?.message }}</p>
    <template #footer>
      <Button v-if="!dialogState?.hideCancel" label="Cancelar" severity="secondary" text @click="done(false)" />
      <Button
        :label="dialogState?.okText" :severity="dialogState?.danger ? 'danger' : 'primary'"
        @click="done(true)"
      />
    </template>
  </Dialog>
</template>

<style scoped>
.msg { margin: 0; white-space: pre-line; color: var(--muted); line-height: 1.5; }
</style>
