<script setup lang="ts">
defineProps<{
  label: string
  value: string | number
  icon: string
  hint?: string
  tone?: 'default' | 'ok' | 'warn' | 'danger'
}>()
</script>

<template>
  <div class="stat" :class="tone ?? 'default'">
    <span class="stat-icon"><i :class="['pi', icon]" /></span>
    <div class="stat-value num">{{ value }}</div>
    <div class="stat-label">{{ label }}</div>
    <div v-if="hint" class="tiny">{{ hint }}</div>
  </div>
</template>

<style scoped>
.stat {
  background: var(--surface); border: 1px solid var(--border); border-radius: 14px; padding: 16px;
  box-shadow: 0 1px 2px rgba(20, 40, 20, .05);
}
.stat-icon {
  width: 34px; height: 34px; border-radius: 10px; display: grid; place-items: center;
  background: #eaf3ea; color: var(--leaf); font-size: 15px; margin-bottom: 10px;
}
.stat-value { font-size: 27px; font-weight: 800; letter-spacing: -.03em; line-height: 1.1; }
.stat-label { color: var(--muted); font-size: 13px; margin-top: 2px; font-weight: 600; }
.ok .stat-icon { background: #e7f6ec; color: var(--ok); }
.warn .stat-icon { background: #fdf0e3; color: var(--warn); }
.danger .stat-icon { background: #fdeaea; color: var(--danger); }
.danger .stat-value { color: var(--danger); }
</style>
