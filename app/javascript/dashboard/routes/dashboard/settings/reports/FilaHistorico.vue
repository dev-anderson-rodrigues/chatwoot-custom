<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import DateRangePicker from 'dashboard/components/ui/DateRangePicker.vue';
import ReportHeader from './components/ReportHeader.vue';
import FilaKpiTiles from './components/fila/FilaKpiTiles.vue';
import FilaDailyEvolutionCharts from './components/fila/FilaDailyEvolutionCharts.vue';
import FilaTeamTable from './components/fila/FilaTeamTable.vue';
import FilaCapacityBars from './components/fila/FilaCapacityBars.vue';
import FilaAgentTable from './components/fila/FilaAgentTable.vue';
import {
  useFilaHistoricoReport,
  PERIOD_OPTIONS,
  AGENT_TYPE_OPTIONS,
} from './composables/useFilaHistoricoReport';

const { t } = useI18n();

const teams = useMapGetter('teams/getTeams');

const {
  report,
  loading,
  loaded,
  hasError,
  filters,
  variationOf,
  fetch,
  setPeriod,
  setCustomRange,
  setTeam,
  setAgentType,
} = useFilaHistoricoReport();

const teamOptions = computed(() => [
  { value: '', label: t('REPORT.FILA.ALL_TEAMS') },
  ...teams.value.map(team => ({ value: team.id, label: team.name })),
]);

const onTeamChange = value => setTeam(value ? Number(value) : null);

const agentTypeLabel = value =>
  t(`REPORT.FILA.AGENT_TYPE.${value.toUpperCase()}`);
const periodLabel = value => t(`REPORT.FILA.PERIOD.${value.toUpperCase()}`);

const onCustomRangeChange = ([start, end]) => {
  if (!start || !end) return;
  setCustomRange([start, end]);
};

const isBotFilter = computed(() => filters.agentType === 'bot');

fetch();
</script>

<template>
  <section class="flex flex-col w-full gap-4">
    <ReportHeader
      :header-title="t('REPORT.FILA.TITLE')"
      :header-description="t('REPORT.FILA.DESCRIPTION')"
    />

    <div class="flex flex-wrap items-end gap-3">
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('REPORT.FILA.TEAM_FILTER') }}
        <Select
          :model-value="filters.teamId || ''"
          :options="teamOptions"
          @update:model-value="onTeamChange"
        />
      </label>

      <div
        role="group"
        :aria-label="t('REPORT.FILA.AGENT_TYPE.LABEL')"
        class="flex flex-col gap-1"
      >
        <span class="text-sm text-n-slate-11">{{
          t('REPORT.FILA.AGENT_TYPE.LABEL')
        }}</span>
        <div class="flex items-center gap-1">
          <Button
            v-for="option in AGENT_TYPE_OPTIONS"
            :key="option"
            :label="agentTypeLabel(option)"
            :variant="filters.agentType === option ? 'solid' : 'ghost'"
            :color="filters.agentType === option ? 'blue' : 'slate'"
            :aria-pressed="filters.agentType === option"
            size="sm"
            @click="setAgentType(option)"
          />
        </div>
      </div>

      <div
        role="group"
        :aria-label="t('REPORT.FILA.PERIOD.LABEL')"
        class="flex flex-col gap-1"
      >
        <span class="text-sm text-n-slate-11">{{
          t('REPORT.FILA.PERIOD.LABEL')
        }}</span>
        <div class="flex items-center gap-1">
          <Button
            v-for="option in PERIOD_OPTIONS"
            :key="option"
            :label="periodLabel(option)"
            :variant="filters.period === option ? 'solid' : 'ghost'"
            :color="filters.period === option ? 'blue' : 'slate'"
            :aria-pressed="filters.period === option"
            size="sm"
            @click="setPeriod(option)"
          />
        </div>
      </div>

      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('REPORT.FILA.PERIOD.CUSTOM') }}
        <DateRangePicker
          :value="filters.customRange"
          :confirm-text="t('REPORT.FILA.PERIOD.CUSTOM')"
          @change="onCustomRangeChange"
        />
      </label>
    </div>

    <div v-if="loading && !loaded" class="flex justify-center py-10">
      <Spinner />
    </div>

    <Banner v-else-if="hasError" color="ruby">
      <span class="flex items-center gap-2">
        <span class="size-4 i-lucide-circle-alert" />
        {{ t('REPORT.FILA.ERROR') }}
      </span>
    </Banner>

    <!-- Trocar filtro mantem os numeros anteriores na tela em vez de piscar
         spinner; a opacidade e a pista de que ha consulta em voo. -->
    <div v-else class="flex flex-col gap-6" :class="{ 'opacity-50': loading }">
      <FilaKpiTiles :kpis="report.kpis.current" :variation-of="variationOf" />

      <FilaDailyEvolutionCharts :daily-evolution="report.dailyEvolution" />

      <FilaTeamTable :items="report.byTeam" />

      <FilaCapacityBars :items="report.capacityVsDemand" />

      <FilaAgentTable :items="report.byAgent" :bot-hint="isBotFilter" />

      <!-- O criterio precisa estar na tela: "quem atende" e o mesmo recorte ao
           vivo do Monitoramento/Origem, e abandono so conta resolucao humana
           sem nenhuma resposta -- resolucao do robo nunca conta. -->
      <p class="flex items-start gap-2 m-0 text-xs text-n-slate-11">
        <span class="mt-0.5 size-3.5 shrink-0 i-lucide-info" />
        {{ t('REPORT.FILA.CRITERION') }}
      </p>
    </div>
  </section>
</template>
