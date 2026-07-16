<script setup lang="ts">
import Modal from './Modal.vue'
import { dialogState } from '../composables/dialog'

function done(v: boolean) {
  dialogState.value?.resolve(v)
  dialogState.value = null
}
</script>

<template>
  <Modal v-if="dialogState" :title="dialogState.title" @close="done(false)">
    <p style="margin:0;white-space:pre-line">{{ dialogState.message }}</p>
    <template #actions>
      <button v-if="!dialogState.hideCancel" class="btn-ghost" @click="done(false)">Cancelar</button>
      <button class="btn" :style="dialogState.danger ? 'background:#dc2626' : ''" @click="done(true)">
        {{ dialogState.okText }}
      </button>
    </template>
  </Modal>
</template>
