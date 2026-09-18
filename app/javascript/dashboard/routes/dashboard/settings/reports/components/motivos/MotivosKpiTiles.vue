<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatTime } from '@chatwoot/utils';
import ReportTile from '../ReportTile.vue';

const props = defineProps({
  kpis: { type: Object, required: true },
});

const { t } = useI18n();

const formatCount = value => Number(value).toLocaleString();

// `topReason`/`slowestReason` sao nulos quando nenhum motivo teve ocorrencia no
// periodo. Mostrar um traco e melhor que esconder o tile: o grid manteria buraco
// e a tela pareceria quebrada.
const EMPTY = '—';

const topReasonName = computed(() => props.kpis.topReason?.name ?? EMPTY);

const topReasonDescription = computed(() => {
  const top = props.kpis.topReason;
  if (!top) return '';

  return t('REPORT.MOTIVOS.KPI.TOP_REASON_DESCRIPTION', {
    count: formatCount(top.total),
    pct: top.pct,
  });
});

const slowestReasonName = computed(
  () => props.kpis.slowestReason?.name ?? EMPTY
);

const slowestReasonDescription = computed(() => {
  const slowest = props.kpis.slowestReason;
  if (!slowest) return '';

  return formatTime(slowest.avgHandleSeconds ?? 0);
});
</script>

<template>
  <dl class="grid grid-cols-1 gap-3 m-0 sm:grid-cols-2 xl:grid-cols-5">
    <ReportTile
      :label="t('REPORT.MOTIVOS.KPI.REASONS_COUNT')"
      :value="formatCount(kpis.reasonsCount)"
    />
    <ReportTile
      :label="t('REPORT.MOTIVOS.KPI.CONVERSATIONS_TOTAL')"
      :value="formatCount(kpis.conversationsTotal)"
    />
    <ReportTile
      :label="t('REPORT.MOTIVOS.KPI.TOP_REASON')"
      :value="topReasonName"
      :description="topReasonDescription"
    />
    <ReportTile
      :label="t('REPORT.MOTIVOS.KPI.SLOWEST_REASON')"
      :value="slowestReasonName"
      :description="slowestReasonDescription"
    />
    <ReportTile
      :label="t('REPORT.MOTIVOS.KPI.AVG_FCR')"
      :value="`${kpis.avgFcr}%`"
      :description="t('REPORT.MOTIVOS.KPI.AVG_FCR_DESCRIPTION')"
    />
  </dl>
</template>
