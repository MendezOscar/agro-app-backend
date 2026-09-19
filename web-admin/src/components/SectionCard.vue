<script setup lang="ts">
defineProps<{ title?: string; subtitle?: string; icon?: string; flush?: boolean }>()
</script>

<template>
  <section class="sc" :class="{ flush }">
    <header v-if="title || $slots.actions" class="sc-head">
      <div class="sc-title">
        <i v-if="icon" :class="['pi', icon]" />
        <div>
          <h3>{{ title }}</h3>
          <p v-if="subtitle" class="muted">{{ subtitle }}</p>
        </div>
      </div>
      <div class="sc-actions"><slot name="actions" /></div>
    </header>
    <div class="sc-body"><slot /></div>
  </section>
</template>

<style scoped>
.sc {
  background: var(--surface); border: 1px solid var(--border); border-radius: 14px;
  box-shadow: 0 1px 2px rgba(20, 40, 20, .05); overflow: hidden;
}
.sc-head {
  display: flex; align-items: flex-start; gap: 12px; flex-wrap: wrap;
  padding: 15px 18px; border-bottom: 1px solid var(--border);
}
.sc-title { display: flex; align-items: flex-start; gap: 10px; flex: 1; min-width: 0; }
.sc-title i { color: var(--leaf); font-size: 16px; margin-top: 2px; }
.sc-title h3 { font-size: 15.5px; font-weight: 700; }
.sc-title p { margin: 2px 0 0; }
.sc-actions { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.sc-body { padding: 18px; }
.sc.flush .sc-body { padding: 0; }
</style>
