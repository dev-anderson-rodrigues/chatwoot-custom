<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import {
  useMacroStats,
  PERIOD_OPTIONS,
} from 'dashboard/composables/useMacroStats';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const { t } = useI18n();

const { period, loading, hasError, totals, ranking, isEmpty, fetchStats } =
  useMacroStats();

const formatRate = rate => (rate === null ? '—' : `${rate}%`);

// A cor reforca o numero, nunca o substitui: a taxa aparece escrita ao lado.
const rateColor = rate => {
  if (rate === null) return 'text-n-slate-10';
  if (rate >= 90) return 'text-n-teal-11';
  if (rate >= 60) return 'text-n-amber-11';
  return 'text-n-ruby-11';
};

const tiles = computed(() => [
  {
    key: 'executions',
    label: t('MACROS.STATS.TOTAL_EXECUTIONS'),
    value: totals.value.executions,
    color: 'text-n-slate-12',
  },
  {
    key: 'successRate',
    label: t('MACROS.STATS.SUCCESS_RATE'),
    value: formatRate(totals.value.successRate),
    color: rateColor(totals.value.successRate),
  },
  {
    key: 'failures',
    label: t('MACROS.STATS.FAILED'),
    // Zero falhas em vermelho seria alarme falso.
    value: totals.value.failures,
    color: totals.value.failures > 0 ? 'text-n-ruby-11' : 'text-n-slate-12',
  },
  {
    key: 'activeMacros',
    label: t('MACROS.STATS.ACTIVE_MACROS'),
    value: totals.value.activeMacros,
    color: 'text-n-slate-12',
  },
]);

const lastRunLabel = row =>
  t('MACROS.STATS.LAST_RUN', {
    time: messageTimestamp(row.lastExecutedAt, 'MMM dd, yyyy'),
  });

onMounted(fetchStats);
</script>

<template>
  <section
    class="flex flex-col gap-4 p-4 mb-4 border rounded-lg border-n-weak bg-n-solid-1"
    :aria-busy="loading"
  >
    <header class="flex flex-wrap items-center justify-between gap-3">
      <h3 class="m-0 text-base font-medium text-n-slate-12">
        {{ t('MACROS.STATS.TITLE') }}
      </h3>
      <!-- Rotulo proprio, nao o titulo da secao: um grupo chamado "Visao geral"
           dentro de uma secao chamada "Visao geral" nao diz ao leitor de tela
           que ali se escolhe o periodo. -->
      <div
        role="group"
        :aria-label="t('MACROS.STATS.PERIOD_GROUP_LABEL')"
        class="flex items-center gap-1"
      >
        <Button
          v-for="option in PERIOD_OPTIONS"
          :key="option"
          :label="t(`MACROS.STATS.PERIOD_${option}D`)"
          :variant="period === option ? 'solid' : 'ghost'"
          :color="period === option ? 'blue' : 'slate'"
          :aria-pressed="period === option"
          size="sm"
          @click="period = option"
        />
      </div>
    </header>

    <div v-if="loading && isEmpty" class="flex justify-center py-10">
      <Spinner />
    </div>

    <div
      v-else-if="hasError"
      class="flex items-center gap-2 px-4 py-3 text-sm rounded-lg text-n-ruby-11 bg-n-ruby-3"
    >
      <span class="size-4 i-lucide-circle-alert" />
      {{ t('MACROS.STATS.ERROR') }}
    </div>

    <p v-else-if="isEmpty" class="m-0 py-6 text-sm text-center text-n-slate-11">
      {{ t('MACROS.STATS.NO_DATA') }}
    </p>

    <!-- Trocar de periodo mantem na tela os numeros do periodo anterior em vez
         de piscar um spinner; a opacidade e a pista de que ha consulta em voo. -->
    <div v-else class="flex flex-col gap-4" :class="{ 'opacity-50': loading }">
      <dl class="grid grid-cols-2 gap-3 m-0 sm:grid-cols-4">
        <div
          v-for="tile in tiles"
          :key="tile.key"
          class="flex flex-col p-3 border rounded-lg border-n-weak bg-n-alpha-1"
        >
          <dt class="text-xs tracking-wide uppercase text-n-slate-11">
            {{ tile.label }}
          </dt>
          <dd
            class="m-0 mt-1 text-2xl font-semibold tabular-nums"
            :class="tile.color"
          >
            {{ tile.value }}
          </dd>
        </div>
      </dl>

      <div v-if="ranking.length" class="flex flex-col gap-2">
        <h4 class="m-0 text-xs font-semibold uppercase text-n-slate-11">
          {{ t('MACROS.STATS.TOP_MACROS') }}
        </h4>
        <ul class="flex flex-col gap-1 m-0 list-none">
          <li
            v-for="row in ranking"
            :key="row.macroId"
            class="flex items-center gap-3 px-2 py-1.5 rounded-md hover:bg-n-alpha-1"
          >
            <div class="flex flex-col min-w-0 gap-0.5 flex-1">
              <span class="text-sm truncate text-n-slate-12">
                {{ row.name }}
              </span>
              <span v-if="row.lastExecutedAt" class="text-xs text-n-slate-11">
                {{ lastRunLabel(row) }}
              </span>
            </div>
            <span
              class="text-xs whitespace-nowrap text-n-slate-11 tabular-nums"
            >
              {{ t('MACROS.STATS.RUNS', { count: row.total }, row.total) }}
            </span>
            <span
              class="w-16 text-xs font-medium text-end tabular-nums"
              :class="rateColor(row.successRate)"
            >
              {{ formatRate(row.successRate) }}
            </span>
          </li>
        </ul>
      </div>
    </div>
  </section>
</template>
