<script setup>
import { useI18n } from 'vue-i18n';
import { formatTime } from '@chatwoot/utils';

defineProps({
  alerts: { type: Array, default: () => [] },
});

const { t } = useI18n();

// Mesmo defeito que a tabela tinha: minutos crus viravam numero gigante numa
// conversa esquecida ha semanas ("64852 min esperando").
const waitingLabel = minutes =>
  t('REPORT.SUPERVISOR.ALERTS.MINUTES', { duration: formatTime(minutes * 60) });
</script>

<template>
  <section class="flex flex-col gap-2">
    <h3
      class="flex items-center gap-1.5 m-0 text-sm font-medium text-n-ruby-11"
    >
      <span class="size-3.5 i-lucide-alarm-clock" />
      {{ t('REPORT.SUPERVISOR.ALERTS.TITLE') }}
    </h3>

    <p v-if="!alerts.length" class="m-0 text-sm text-n-slate-11">
      {{ t('REPORT.SUPERVISOR.ALERTS.EMPTY') }}
    </p>

    <ul
      v-else
      class="flex flex-col gap-1 p-0 m-0 list-none max-h-80 overflow-y-auto"
    >
      <li
        v-for="alert in alerts"
        :key="alert.id"
        class="flex items-center justify-between gap-2 px-3 py-2 border rounded-lg border-n-ruby-4 bg-n-ruby-2"
      >
        <div class="flex flex-col min-w-0">
          <span class="text-sm truncate text-n-slate-12">{{
            alert.contactName || '—'
          }}</span>
          <span class="text-xs truncate text-n-slate-11">{{
            alert.inboxName
          }}</span>
        </div>
        <span class="text-xs font-medium tabular-nums shrink-0 text-n-ruby-11">
          {{ waitingLabel(alert.minutes) }}
        </span>
      </li>
    </ul>
  </section>
</template>
