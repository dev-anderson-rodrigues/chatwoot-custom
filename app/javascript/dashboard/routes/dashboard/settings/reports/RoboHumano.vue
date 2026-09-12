<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatTime } from '@chatwoot/utils';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ReportHeader from './components/ReportHeader.vue';
import ReportTile from './components/ReportTile.vue';
import {
  useOwnershipReport,
  PERIOD_OPTIONS,
} from './composables/useOwnershipReport';

const { t } = useI18n();

const {
  current,
  loading,
  loaded,
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
    // Resolver mais sozinho e bom; precisar de mais gente, nem sempre -- por
    // isso so esta metrica tem cor, e o resto fica neutro.
    variationMeaning: 'up-is-good',
  },
  {
    key: 'human',
    label: t('REPORT.OWNERSHIP.KPI.HUMAN_RESOLUTIONS'),
    value: current.value.humanResolutions,
    variation: humanResolutionsVariation.value,
  },
  {
    key: 'share',
    label: t('REPORT.OWNERSHIP.KPI.BOT_SHARE'),
    value: botShare.value === null ? SEM_DADO : `${botShare.value}%`,
  },
  {
    key: 'handoffs',
    label: t('REPORT.OWNERSHIP.KPI.HANDOFFS'),
    value: current.value.handoffs,
    variation: handoffsVariation.value,
  },
  {
    key: 'botTime',
    label: t('REPORT.OWNERSHIP.KPI.BOT_AVG_RESOLUTION'),
    value: duracao(current.value.botAvgResolutionSeconds),
  },
  {
    key: 'humanTime',
    label: t('REPORT.OWNERSHIP.KPI.HUMAN_AVG_RESOLUTION'),
    value: duracao(current.value.humanAvgResolutionSeconds),
  },
  {
    key: 'firstResponse',
    label: t('REPORT.OWNERSHIP.KPI.FIRST_RESPONSE'),
    value: duracao(current.value.humanAvgFirstResponseSeconds),
  },
]);

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

    <!-- Spinner so na primeira carga. Depois, trocar o periodo mantem os
         numeros anteriores esmaecidos: usar `botResolutions` aqui fazia a tela
         piscar spinner a cada filtro em toda conta que tem zero encerradas pelo
         robo, que e um caso normal. -->
    <div v-if="loading && !loaded" class="flex justify-center py-10">
      <Spinner />
    </div>

    <Banner v-else-if="hasError" color="ruby">
      <span class="flex items-center gap-2">
        <span class="size-4 i-lucide-circle-alert" />
        {{ t('REPORT.OWNERSHIP.ERROR') }}
      </span>
    </Banner>

    <div v-else class="flex flex-col gap-4" :class="{ 'opacity-50': loading }">
      <dl class="grid grid-cols-2 gap-3 m-0 sm:grid-cols-3 xl:grid-cols-4">
        <ReportTile
          v-for="tile in tiles"
          :key="tile.key"
          :label="tile.label"
          :value="tile.value"
          :variation="tile.variation ?? null"
          :variation-meaning="tile.variationMeaning ?? 'neutral'"
          :variation-title="t('REPORT.OWNERSHIP.VARIATION')"
        />
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
