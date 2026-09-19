<script setup lang="ts">
defineProps<{ icon?: string; text: string; hint?: string }>()
</script>

<template>
  <div class="empty">
    <i :class="['pi', icon ?? 'pi-inbox']" />
    <p>{{ text }}</p>
    <p v-if="hint" class="tiny">{{ hint }}</p>
  </div>
</template>

<style scoped>
.empty { text-align: center; padding: 26px 14px; color: var(--muted); }
.empty i { font-size: 24px; opacity: .45; }
.empty p { margin: 8px 0 0; font-size: 13.5px; }
</style>
