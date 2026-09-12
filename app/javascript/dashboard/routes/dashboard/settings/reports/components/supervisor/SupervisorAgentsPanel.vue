<script setup>
import { useI18n } from 'vue-i18n';
import Label from 'dashboard/components-next/label/Label.vue';

defineProps({
  agents: { type: Array, default: () => [] },
});

const { t } = useI18n();

const STATUS_COLORS = { online: 'teal', busy: 'amber', offline: 'slate' };

const statusLabel = status =>
  t(
    `REPORT.SUPERVISOR.AGENTS_PANEL.STATUS.${(status || 'offline').toUpperCase()}`
  );
</script>

<template>
  <section class="flex flex-col gap-2">
    <h3 class="m-0 text-sm font-medium text-n-slate-12">
      {{ t('REPORT.SUPERVISOR.AGENTS_PANEL.TITLE') }}
    </h3>

    <p v-if="!agents.length" class="m-0 text-sm text-n-slate-11">
      {{ t('REPORT.SUPERVISOR.AGENTS_PANEL.EMPTY') }}
    </p>

    <ul
      v-else
      class="flex flex-col gap-1 p-0 m-0 list-none max-h-80 overflow-y-auto"
    >
      <li
        v-for="agent in agents"
        :key="agent.id"
        class="flex items-center justify-between gap-2 px-3 py-2 border rounded-lg border-n-weak bg-n-alpha-1"
      >
        <span class="text-sm truncate text-n-slate-12">{{ agent.name }}</span>
        <span class="flex items-center gap-2 shrink-0">
          <span class="text-xs tabular-nums text-n-slate-11">
            {{
              t('REPORT.SUPERVISOR.AGENTS_PANEL.LOAD', { count: agent.load })
            }}
          </span>
          <Label
            :label="statusLabel(agent.status)"
            :color="STATUS_COLORS[agent.status] || 'slate'"
            compact
          />
        </span>
      </li>
    </ul>
  </section>
</template>
