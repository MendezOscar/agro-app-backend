<script setup lang="ts">
interface StageLike { id?: string; kind: number; status: number; note?: string }

withDefaults(defineProps<{ stages: StageLike[]; activeId?: string | null; interactive?: boolean }>(), {
  activeId: null,
  interactive: false,
})
const emit = defineEmits<{ select: [id: string] }>()

const labels = ['Planificación', 'Prep. suelo', 'Siembra', 'Manejo', 'Monitoreo', 'Cosecha', 'Poscosecha', 'Evaluación']
const dotClass = (status: number) => ['is-pending', 'is-progress', 'is-done'][status] ?? 'is-pending'
</script>

<template>
  <div class="track" :class="{ interactive }">
    <component
      v-for="(s, i) in stages" :key="s.id ?? s.kind"
      :is="interactive ? 'button' : 'div'"
      class="step"
      :class="{ active: interactive && activeId === s.id }"
      @click="interactive && s.id ? emit('select', s.id) : undefined"
    >
      <div class="line">
        <span class="bar" :class="i === 0 ? 'ghost' : dotClass(stages[i - 1].status)" />
        <span class="dot" :class="dotClass(s.status)">
          <i v-if="s.status === 2" class="pi pi-check" />
          <template v-else>{{ s.kind + 1 }}</template>
        </span>
        <span class="bar" :class="i === stages.length - 1 ? 'ghost' : dotClass(s.status)" />
      </div>
      <div class="label">{{ labels[s.kind] }}</div>
      <div v-if="s.note" class="note num">{{ s.note }}</div>
    </component>
  </div>
</template>

<style scoped>
.track { display: flex; align-items: flex-start; overflow-x: auto; padding-bottom: 4px; }
.step {
  flex: 1; min-width: 74px; display: flex; flex-direction: column; align-items: center;
  background: none; border: none; padding: 6px 2px; font: inherit; color: inherit;
}
.track.interactive .step { cursor: pointer; border-radius: 10px; transition: background .15s; }
.track.interactive .step:hover { background: #f2f6f1; }
.track.interactive .step.active { background: #eaf3ea; }
.track.interactive .step.active .label { color: var(--leaf-dark); font-weight: 700; }
.line { display: flex; align-items: center; width: 100%; }
.bar { flex: 1; height: 3px; border-radius: 2px; }
.bar.ghost { background: transparent; }
.bar.is-pending { background: #d7ddd4; }
.bar.is-progress { background: var(--amber); }
.bar.is-done { background: var(--leaf); }
.dot {
  width: 26px; height: 26px; border-radius: 50%; flex-shrink: 0; color: #fff;
  display: grid; place-items: center; font-size: 11.5px; font-weight: 700;
}
.dot i { font-size: 11px; }
.dot.is-pending { background: #b9c2b6; }
.dot.is-progress { background: var(--amber); }
.dot.is-done { background: var(--leaf); }
.label { font-size: 11px; color: var(--muted); text-align: center; margin-top: 6px; line-height: 1.25; }
.note { font-size: 11px; color: var(--leaf-dark); font-weight: 700; margin-top: 2px; }
</style>
