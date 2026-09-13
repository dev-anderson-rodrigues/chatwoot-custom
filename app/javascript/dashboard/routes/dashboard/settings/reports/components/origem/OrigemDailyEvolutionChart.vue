<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import LineChart from 'shared/components/charts/LineChart.vue';

const props = defineProps({
  dailyEvolution: { type: Array, default: () => [] },
});

const { t, locale } = useI18n();

// `date` chega como "AAAA-MM-DD" (Date#to_s do Ruby); Intl formata no idioma
// da tela em vez do "dia/mes" fixo que a fonte montava na mao.
const formatDate = value =>
  new Intl.DateTimeFormat(locale.value, {
    month: 'short',
    day: '2-digit',
  }).format(new Date(`${value}T00:00:00`));

const chartData = computed(() => ({
  categories: props.dailyEvolution.map(day => formatDate(day.date)),
  series: [
    {
      id: 'recebidos',
      label: t('REPORT.ORIGEM.RECEBIDOS'),
      color: 'rgb(var(--blue-9))',
      pointBorderColor: 'rgb(var(--card-color))',
      valueColor: 'rgb(var(--blue-11))',
      data: props.dailyEvolution.map(day => day.recebidos),
    },
    {
      id: 'efetuados',
      label: t('REPORT.ORIGEM.EFETUADOS'),
      color: 'rgb(var(--amber-9))',
      pointBorderColor: 'rgb(var(--card-color))',
      valueColor: 'rgb(var(--amber-11))',
      data: props.dailyEvolution.map(day => day.efetuados),
    },
  ],
}));

const formatCount = value => Number(value).toLocaleString();

const hasData = computed(() => props.dailyEvolution.length > 0);
</script>

<template>
  <section class="flex flex-col gap-1">
    <h3 class="m-0 text-sm font-medium text-n-slate-12">
      {{ t('REPORT.ORIGEM.CHART.TITLE') }}
    </h3>
    <p class="m-0 mb-2 text-xs text-n-slate-10">
      {{ t('REPORT.ORIGEM.CHART.HINT') }}
    </p>

    <LineChart
      v-if="hasData"
      :data="chartData"
      :format-value="formatCount"
      :height="220"
      :point-radius="3"
      :aria-label="t('REPORT.ORIGEM.CHART.TITLE')"
    />
    <div
      v-else
      class="grid h-[220px] text-sm place-content-center text-n-slate-11"
    >
      {{ t('REPORT.ORIGEM.CHART.EMPTY') }}
    </div>
  </section>
</template>
