<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useLocale } from 'shared/composables/useLocale';
import BarChart from 'shared/components/charts/BarChart.vue';
import LineChart from 'shared/components/charts/LineChart.vue';

const props = defineProps({
  dailyEvolution: { type: Array, default: () => [] },
});

const { t } = useI18n();
const { resolvedLocale } = useLocale();

// `date` chega como "AAAA-MM-DD" (Date#to_s do Ruby); `locale.value` cru
// (ex.: "pt_BR") derruba o Intl com RangeError -- resolvedLocale ja normaliza
// para o formato BCP 47 que o Intl aceita (mesmo bug da fatia 3, achado so na
// verificacao visual, ver OrigemDailyEvolutionChart.vue).
const formatDate = value =>
  new Intl.DateTimeFormat(resolvedLocale.value, {
    month: 'short',
    day: '2-digit',
  }).format(new Date(`${value}T00:00:00`));

const categories = computed(() =>
  props.dailyEvolution.map(day => formatDate(day.date))
);

const volumeChartData = computed(() => ({
  categories: categories.value,
  series: [
    {
      id: 'volume',
      label: t('REPORT.FILA.CHART.VOLUME_TITLE'),
      color: 'rgb(var(--blue-9))',
      valueColor: 'rgb(var(--blue-11))',
      data: props.dailyEvolution.map(day => day.volume),
    },
  ],
}));

const waitChartData = computed(() => ({
  categories: categories.value,
  series: [
    {
      id: 'avg-wait',
      label: t('REPORT.FILA.CHART.WAIT_TITLE'),
      color: 'rgb(var(--amber-9))',
      pointBorderColor: 'rgb(var(--card-color))',
      valueColor: 'rgb(var(--amber-11))',
      data: props.dailyEvolution.map(day => day.avgWaitMinutes),
    },
  ],
}));

const formatCount = value => Number(value).toLocaleString();
const hasData = computed(() => props.dailyEvolution.length > 0);
</script>

<template>
  <section class="flex flex-col gap-1">
    <div v-if="hasData" class="grid grid-cols-1 gap-6 lg:grid-cols-2">
      <div class="flex flex-col gap-2">
        <h3 class="m-0 text-sm font-medium text-n-slate-12">
          {{ t('REPORT.FILA.CHART.VOLUME_TITLE') }}
        </h3>
        <p class="m-0 mb-2 text-xs text-n-slate-10">
          {{ t('REPORT.FILA.CHART.VOLUME_HINT') }}
        </p>
        <BarChart
          :data="volumeChartData"
          :format-value="formatCount"
          :height="208"
          :aria-label="t('REPORT.FILA.CHART.VOLUME_TITLE')"
        />
      </div>

      <div class="flex flex-col gap-2">
        <h3 class="m-0 text-sm font-medium text-n-slate-12">
          {{ t('REPORT.FILA.CHART.WAIT_TITLE') }}
        </h3>
        <p class="m-0 mb-2 text-xs text-n-slate-10">
          {{ t('REPORT.FILA.CHART.WAIT_HINT') }}
        </p>
        <LineChart
          :data="waitChartData"
          :format-value="formatCount"
          :height="208"
          :point-radius="3"
          :aria-label="t('REPORT.FILA.CHART.WAIT_TITLE')"
        />
      </div>
    </div>
    <div
      v-else
      class="grid h-[208px] text-sm place-content-center text-n-slate-11"
    >
      {{ t('REPORT.FILA.CHART.EMPTY') }}
    </div>
  </section>
</template>
