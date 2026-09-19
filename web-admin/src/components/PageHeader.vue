<script setup lang="ts">
import { useRouter } from 'vue-router'

defineProps<{ title: string; subtitle?: string; back?: boolean }>()
const router = useRouter()
</script>

<template>
  <header class="page-head">
    <div class="page-head-text">
      <button v-if="back" class="back" @click="router.back()">
        <i class="pi pi-arrow-left" /> Volver
      </button>
      <h1>{{ title }}</h1>
      <p v-if="subtitle" class="muted">{{ subtitle }}</p>
    </div>
    <div class="page-head-actions"><slot name="actions" /></div>
  </header>
</template>

<style scoped>
.page-head { display: flex; align-items: flex-end; gap: 16px; flex-wrap: wrap; margin-bottom: 20px; }
.page-head-text { flex: 1; min-width: 220px; }
.page-head h1 { font-size: 25px; font-weight: 800; }
.page-head p { margin: 4px 0 0; }
.page-head-actions { display: flex; gap: 8px; flex-wrap: wrap; }
.back {
  background: none; border: none; padding: 0; margin-bottom: 8px; cursor: pointer;
  color: var(--muted); font-size: 13px; font-weight: 600; display: inline-flex; align-items: center; gap: 6px;
}
.back:hover { color: var(--leaf-dark); }
</style>
