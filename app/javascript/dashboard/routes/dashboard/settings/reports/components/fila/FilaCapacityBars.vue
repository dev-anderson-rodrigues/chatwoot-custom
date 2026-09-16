<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  items: { type: Array, default: () => [] },
});

const { t } = useI18n();

const formatCount = value => Number(value).toLocaleString();

// Tokens do design system, nao hex/rgba crus -- funciona em claro/escuro de
// graca.
const usageBarClass = pct => {
  if (pct >= 90) return 'bg-n-ruby-9';
  if (pct >= 70) return 'bg-n-amber-9';
  return 'bg-n-teal-9';
};
</script>

<template>
  <section class="flex flex-col gap-1">
    <div class="flex items-center gap-1.5">
      <h3 class="m-0 text-sm font-medium text-n-slate-12">
        {{ t('REPORT.FILA.CAPACITY.TITLE') }}
      </h3>
      <span
        v-tooltip.right="t('REPORT.FILA.CAPACITY.HINT')"
        class="text-xs i-lucide-info text-n-slate-10"
      />
    </div>

    <div v-if="!items.length" class="py-6 text-sm text-center text-n-slate-10">
      {{ t('REPORT.FILA.CAPACITY.EMPTY') }}
    </div>

    <div v-else class="flex flex-col gap-3">
      <div
        v-for="team in items"
        :key="team.id ?? 'none'"
        class="flex items-center gap-3"
      >
        <span
          class="flex-shrink-0 text-sm truncate text-n-slate-11 w-36"
          :title="team.name || t('REPORT.FILA.TEAM.NO_TEAM')"
        >
          {{ team.name || t('REPORT.FILA.TEAM.NO_TEAM') }}
        </span>
        <div class="flex-1 h-3 overflow-hidden rounded bg-n-alpha-2">
          <div
            class="h-full transition-all duration-500 rounded"
            :class="usageBarClass(team.usagePct)"
            :style="{ width: `${Math.min(team.usagePct, 100)}%` }"
          />
        </div>
        <span class="flex-shrink-0 text-xs text-right text-n-slate-11 w-10">
          {{ team.usagePct }}%
        </span>
        <span class="flex-shrink-0 text-xs text-right text-n-slate-10 w-32">
          {{ formatCount(team.demand) }} / {{ formatCount(team.capacity) }} ({{
            t('REPORT.FILA.CAPACITY.AGENTS', { count: team.agents })
          }})
        </span>
      </div>
    </div>
  </section>
</template>
