<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatTime } from '@chatwoot/utils';
import ReportTile from '../ReportTile.vue';

const props = defineProps({
  kpis: {
    type: Object,
    required: true,
  },
  variationOf: {
    type: Function,
    required: true,
  },
});

const { t } = useI18n();

const totalVariation = props.variationOf('total');
const avgWaitVariation = props.variationOf('avgWaitSeconds');
const maxWaitVariation = props.variationOf('maxWaitSeconds');
const abandonRateVariation = props.variationOf('abandonRate');

const formatCount = value => Number(value).toLocaleString();
const formatDuration = seconds => formatTime(seconds ?? 0);

const tiles = computed(() => [
  {
    key: 'total',
    label: t('REPORT.FILA.KPI.TOTAL'),
    value: formatCount(props.kpis.total),
    description: t('REPORT.FILA.KPI.TOTAL_DESC'),
    variation: totalVariation.value,
    // Mais volume nao e bom nem ruim -- pintar de verde ou vermelho seria
    // opinion disfarcada de dado (mesmo raciocinio do proprio ReportTile.vue).
    variationMeaning: 'neutral',
  },
  {
    key: 'avg-wait',
    label: t('REPORT.FILA.KPI.AVG_WAIT'),
    value: formatDuration(props.kpis.avgWaitSeconds),
    description: t('REPORT.FILA.KPI.AVG_WAIT_DESC'),
    variation: avgWaitVariation.value,
    variationMeaning: 'down-is-good',
  },
  {
    key: 'max-wait',
    label: t('REPORT.FILA.KPI.MAX_WAIT'),
    value: formatDuration(props.kpis.maxWaitSeconds),
    description: t('REPORT.FILA.KPI.MAX_WAIT_DESC'),
    variation: maxWaitVariation.value,
    variationMeaning: 'down-is-good',
  },
  {
    key: 'abandon-rate',
    label: t('REPORT.FILA.KPI.ABANDON_RATE'),
    value: `${props.kpis.abandonRate}%`,
    description: t('REPORT.FILA.KPI.ABANDON_RATE_DESC', {
      count: formatCount(props.kpis.abandonedCount),
    }),
    variation: abandonRateVariation.value,
    variationMeaning: 'down-is-good',
  },
]);
</script>

<template>
  <dl class="grid grid-cols-1 gap-3 m-0 sm:grid-cols-2 xl:grid-cols-4">
    <ReportTile
      v-for="tile in tiles"
      :key="tile.key"
      :label="tile.label"
      :value="tile.value"
      :description="tile.description"
      :variation="tile.variation"
      :variation-meaning="tile.variationMeaning"
      :variation-title="t('REPORT.FILA.VARIATION')"
    />
  </dl>
</template>
