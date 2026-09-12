<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatTime } from '@chatwoot/utils';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ReportHeader from './components/ReportHeader.vue';
import {
  useOwnershipReport,
  PERIOD_OPTIONS,
} from './composables/useOwnershipReport';

const { t } = useI18n();

const {
  current,
  loading,
  hasError,
  filters,
  isEmpty,
  botShare,
  variationOf,
  fetch,
  setPeriod,
} = useOwnershipReport();

const SEM_DADO = '—';

const duracao = segundos => (segundos ? formatTime(segundos) : SEM_DADO);

const botResolutionsVariation = variationOf('botResolutions');
const humanResolutionsVariation = variationOf('humanResolutions');
const handoffsVariation = variationOf('handoffs');

const tiles = computed(() => [
  {
    key: 'bot',
    label: t('REPORT.OWNERSHIP.KPI.BOT_RESOLUTIONS'),
    value: current.value.botResolutions,
    variation: botResolutionsVariation.value,
    // Resolver mais sozinho e bom; precisar de mais gente, nem sempre.
    higherIsBetter: true,
  },
  {
    key: 'human',
    label: t('REPORT.OWNERSHIP.KPI.HUMAN_RESOLUTIONS'),
    value: current.value.humanResolutions,
    variation: humanResolutionsVariation.value,
    higherIsBetter: null,
  },
  {
    key: 'share',
    label: t('REPORT.OWNERSHIP.KPI.BOT_SHARE'),
    value: botShare.value === null ? SEM_DADO : `${botShare.value}%`,
    variation: null,
    higherIsBetter: null,
  },
  {
    key: 'handoffs',
    label: t('REPORT.OWNERSHIP.KPI.HANDOFFS'),
    value: current.value.handoffs,
    variation: handoffsVariation.value,
    higherIsBetter: null,
  },
  {
    key: 'botTime',
    label: t('REPORT.OWNERSHIP.KPI.BOT_AVG_RESOLUTION'),
    value: duracao(current.value.botAvgResolutionSeconds),
    variation: null,
    higherIsBetter: null,
  },
  {
    key: 'humanTime',
    label: t('REPORT.OWNERSHIP.KPI.HUMAN_AVG_RESOLUTION'),
    value: duracao(current.value.humanAvgResolutionSeconds),
    variation: null,
    higherIsBetter: null,
  },
  {
    key: 'firstResponse',
    label: t('REPORT.OWNERSHIP.KPI.FIRST_RESPONSE'),
    value: duracao(current.value.humanAvgFirstResponseSeconds),
    variation: null,
    higherIsBetter: null,
  },
]);

const corDaVariacao = tile => {
  if (tile.variation === null || tile.higherIsBetter === null)
    return 'text-n-slate-11';

  const bom = tile.higherIsBetter ? tile.variation > 0 : tile.variation < 0;

  return bom ? 'text-n-teal-11' : 'text-n-ruby-11';
};

const textoDaVariacao = tile =>
  `${tile.variation > 0 ? '+' : ''}${tile.variation}%`;

onMounted(fetch);
</script>

<template>
  <section class="flex flex-col w-full gap-4">
    <ReportHeader
      :header-title="t('REPORT.OWNERSHIP.TITLE')"
      :header-description="t('REPORT.OWNERSHIP.DESCRIPTION')"
    />

    <div
      role="group"
      :aria-label="t('REPORT.OWNERSHIP.PERIOD.LABEL')"
      class="flex items-center gap-1"
    >
      <Button
        v-for="option in PERIOD_OPTIONS"
        :key="option"
        :label="t(`REPORT.OWNERSHIP.PERIOD.${option.toUpperCase()}`)"
        :variant="filters.period === option ? 'solid' : 'ghost'"
        :color="filters.period === option ? 'blue' : 'slate'"
        :aria-pressed="filters.period === option"
        size="sm"
        @click="setPeriod(option)"
      />
    </div>

    <div
      v-if="loading && !current.botResolutions"
      class="flex justify-center py-10"
    >
      <Spinner />
    </div>

    <div
      v-else-if="hasError"
      class="flex items-center gap-2 px-4 py-3 text-sm rounded-lg text-n-ruby-11 bg-n-ruby-3"
    >
      <span class="size-4 i-lucide-circle-alert" />
      {{ t('REPORT.OWNERSHIP.ERROR') }}
    </div>

    <div v-else class="flex flex-col gap-4" :class="{ 'opacity-50': loading }">
      <dl class="grid grid-cols-2 gap-3 m-0 sm:grid-cols-3 xl:grid-cols-4">
        <div
          v-for="tile in tiles"
          :key="tile.key"
          class="flex flex-col p-3 border rounded-lg border-n-weak bg-n-alpha-1"
        >
          <dt class="text-xs tracking-wide uppercase text-n-slate-11">
            {{ tile.label }}
          </dt>
          <dd
            class="flex items-baseline gap-2 m-0 mt-1 text-2xl font-semibold tabular-nums text-n-slate-12"
          >
            {{ tile.value }}
            <span
              v-if="tile.variation !== null"
              class="text-xs font-medium tabular-nums"
              :class="corDaVariacao(tile)"
              :title="t('REPORT.OWNERSHIP.VARIATION')"
            >
              {{ textoDaVariacao(tile) }}
            </span>
          </dd>
        </div>
      </dl>

      <p v-if="isEmpty" class="m-0 text-sm text-n-slate-11">
        {{ t('REPORT.OWNERSHIP.EMPTY') }}
      </p>

      <!-- O criterio precisa estar na tela: o relatorio de Robos do upstream
           conta "resolvido pelo bot" de outro jeito, e duas telas com numeros
           diferentes sem explicacao viram desconfianca. -->
      <p class="flex items-start gap-2 m-0 text-xs text-n-slate-11">
        <span class="mt-0.5 size-3.5 shrink-0 i-lucide-info" />
        {{ t('REPORT.OWNERSHIP.CRITERION') }}
      </p>
    </div>
  </section>
</template>
