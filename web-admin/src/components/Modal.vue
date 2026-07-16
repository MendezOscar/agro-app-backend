<script setup lang="ts">
defineProps<{ title?: string; width?: string }>()
const emit = defineEmits<{ close: [] }>()
</script>

<template>
  <Teleport to="body">
    <div class="modal-backdrop" @click.self="emit('close')">
      <div class="modal-card" :style="{ maxWidth: width ?? '420px' }">
        <div class="modal-head">
          <h3 style="margin:0">{{ title }}</h3>
          <button class="modal-x" @click="emit('close')" aria-label="Cerrar">✕</button>
        </div>
        <div class="modal-body"><slot /></div>
        <div class="modal-foot"><slot name="actions" /></div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.modal-backdrop {
  position: fixed; inset: 0; background: rgba(26, 31, 26, 0.45);
  display: flex; align-items: center; justify-content: center; padding: 20px; z-index: 1000;
}
.modal-card {
  width: 100%; background: var(--paper, #fff); border-radius: 16px;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.25); overflow: hidden;
  animation: pop 0.14s ease-out;
}
@keyframes pop { from { transform: scale(0.96); opacity: 0 } to { transform: scale(1); opacity: 1 } }
.modal-head {
  display: flex; align-items: center; justify-content: space-between;
  padding: 16px 20px; border-bottom: 1px solid var(--border, #e6e9e3);
}
.modal-x { background: none; border: none; font-size: 18px; cursor: pointer; color: #888; line-height: 1; }
.modal-body { padding: 20px; }
.modal-foot {
  display: flex; justify-content: flex-end; gap: 10px;
  padding: 14px 20px; border-top: 1px solid var(--border, #e6e9e3);
}
</style>
