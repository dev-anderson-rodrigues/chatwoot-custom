<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useLocale } from 'shared/composables/useLocale';
import LineChart from 'shared/components/charts/LineChart.vue';

const props = defineProps({
  evolution: { type: Object, default: () => ({ labels: [], series: [] }) },
});

const { t } = useI18n();
const { resolvedLocale } = useLocale();

// `labels` chega como "AAAA-MM-DD" (Date#to_s do Ruby), a segunda-feira da
// semana. `locale.value` cru (ex.: "pt_BR") derruba o Intl com RangeError --
// `resolvedLocale` normaliza para BCP 47 (mesmo bug da fatia 3, achado so na
// verificacao visual).
const formatWeek = value =>
  new Intl.DateTimeFormat(resolvedLocale.value, {
    month: 'short',
    day: '2-digit',
  }).format(new Date(`${value}T00:00:00`));

const NEUTRAL_COLOR = 'rgb(var(--slate-8))';

const chartData = computed(() => ({
  categories: props.evolution.labels.map(formatWeek),
  series: props.evolution.series.map(serie => ({
    id: serie.name,
    label: serie.name,
    color: serie.color || NEUTRAL_COLOR,
    pointBorderColor: 'rgb(var(--card-color))',
    data: serie.data,
  })),
}));

const formatCount = value => Number(value).toLocaleString();
const hasData = computed(() => props.evolution.series.length > 0);
</script>

<template>
  <section class="flex flex-col gap-2">
    <h3 class="m-0 text-sm font-medium text-n-slate-12">
      {{ t('REPORT.MOTIVOS.CHART.TITLE') }}
    </h3>
    <p class="m-0 mb-2 text-xs text-n-slate-10">
      {{ t('REPORT.MOTIVOS.CHART.HINT') }}
    </p>

    <template v-if="hasData">
      <!-- Legenda propria: o wrapper do LineChart nao expoe uma, e as telas
           irmas da onda tem uma serie so (nao precisavam). Com tres motivos no
           mesmo grafico, tres linhas coloridas sem rotulo nao dizem qual e
           qual -- achado da verificacao visual. -->
      <ul class="flex flex-wrap items-center gap-x-4 gap-y-1 p-0 m-0 list-none">
        <li
          v-for="serie in chartData.series"
          :key="serie.id"
          class="flex items-center gap-1.5 text-xs text-n-slate-11"
        >
          <span
            class="rounded-full size-2.5 shrink-0"
            :style="{ backgroundColor: serie.color }"
            aria-hidden="true"
          />
          {{ serie.label }}
        </li>
      </ul>

      <LineChart
        :data="chartData"
        :format-value="formatCount"
        :height="240"
        :point-radius="3"
        :aria-label="t('REPORT.MOTIVOS.CHART.TITLE')"
      />
    </template>
    <div
      v-else
      class="grid h-[240px] text-sm place-content-center text-n-slate-11"
    >
      {{ t('REPORT.MOTIVOS.CHART.EMPTY') }}
    </div>
  </section>
</template>
