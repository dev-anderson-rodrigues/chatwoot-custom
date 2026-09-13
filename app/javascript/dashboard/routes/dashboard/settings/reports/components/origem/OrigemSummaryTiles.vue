<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ReportTile from '../ReportTile.vue';

const props = defineProps({
  summary: {
    type: Object,
    default: () => ({
      total: 0,
      recebidos: 0,
      efetuados: 0,
      recebidosPct: 0,
      efetuadosPct: 0,
    }),
  },
});

const { t } = useI18n();

// `toLocaleString()` sem locale explicito usa o do navegador -- mesmo padrao
// que `ResolutionFlowCard`/`ResolutionTrendCard` (Captain) ja usam, em vez do
// `n()` do vue-i18n (este projeto nao configura `numberFormats`) ou do
// `pt-BR` fixo que a fonte usava.
const formatCount = value => Number(value).toLocaleString();

const tiles = computed(() => [
  {
    key: 'total',
    label: t('REPORT.ORIGEM.SUMMARY.TOTAL'),
    value: formatCount(props.summary.total),
    description: t('REPORT.ORIGEM.SUMMARY.TOTAL_DESC', {
      count: formatCount(props.summary.total),
    }),
  },
  {
    key: 'recebidos',
    label: t('REPORT.ORIGEM.RECEBIDOS'),
    value: formatCount(props.summary.recebidos),
    description: t('REPORT.ORIGEM.SUMMARY.RECEBIDOS_DESC', {
      pct: props.summary.recebidosPct,
    }),
  },
  {
    key: 'efetuados',
    label: t('REPORT.ORIGEM.EFETUADOS'),
    value: formatCount(props.summary.efetuados),
    description: t('REPORT.ORIGEM.SUMMARY.EFETUADOS_DESC', {
      pct: props.summary.efetuadosPct,
    }),
  },
]);
</script>

<template>
  <dl class="grid grid-cols-1 gap-3 m-0 sm:grid-cols-3">
    <ReportTile
      v-for="tile in tiles"
      :key="tile.key"
      :label="tile.label"
      :value="tile.value"
      :description="tile.description"
    />
  </dl>
</template>
