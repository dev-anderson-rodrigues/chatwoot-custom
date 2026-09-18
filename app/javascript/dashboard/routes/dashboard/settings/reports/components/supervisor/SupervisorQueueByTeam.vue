<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  teams: { type: Array, default: () => [] },
});

const { t } = useI18n();
</script>

<template>
  <section class="flex flex-col gap-2">
    <h3 class="m-0 text-sm font-medium text-n-slate-12">
      {{ t('REPORT.SUPERVISOR.QUEUE_BY_TEAM.TITLE') }}
    </h3>

    <p v-if="!teams.length" class="m-0 text-sm text-n-slate-11">
      {{ t('REPORT.SUPERVISOR.QUEUE_BY_TEAM.EMPTY') }}
    </p>

    <div v-else class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <div
        v-for="team in teams"
        :key="team.id ?? 'no-team'"
        class="flex flex-col gap-2 p-3 border rounded-lg border-n-weak bg-n-alpha-1"
      >
        <span class="text-sm font-medium truncate text-n-slate-12">
          {{ team.name || t('REPORT.SUPERVISOR.QUEUE_BY_TEAM.NO_TEAM') }}
        </span>
        <dl class="grid grid-cols-3 gap-2 m-0">
          <div class="flex flex-col">
            <dt class="text-xs text-n-slate-10">
              {{ t('REPORT.SUPERVISOR.QUEUE_BY_TEAM.IN_QUEUE') }}
            </dt>
            <dd class="m-0 text-sm font-semibold tabular-nums text-n-slate-12">
              {{ team.inQueue }}
            </dd>
          </div>
          <div class="flex flex-col">
            <dt class="text-xs text-n-slate-10">
              {{ t('REPORT.SUPERVISOR.QUEUE_BY_TEAM.IN_PROGRESS') }}
            </dt>
            <dd class="m-0 text-sm font-semibold tabular-nums text-n-slate-12">
              {{ team.inProgress }}
            </dd>
          </div>
          <div class="flex flex-col">
            <dt class="text-xs text-n-slate-10">
              {{ t('REPORT.SUPERVISOR.QUEUE_BY_TEAM.AGENTS_ONLINE') }}
            </dt>
            <dd class="m-0 text-sm font-semibold tabular-nums text-n-teal-11">
              {{ team.agentsOnline }}
            </dd>
          </div>
        </dl>
      </div>
    </div>
  </section>
</template>
