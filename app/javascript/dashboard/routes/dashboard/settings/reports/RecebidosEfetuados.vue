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
import OrigemSummaryTiles from './components/origem/OrigemSummaryTiles.vue';
import OrigemDailyEvolutionChart from './components/origem/OrigemDailyEvolutionChart.vue';
import OrigemBreakdown from './components/origem/OrigemBreakdown.vue';
import OrigemComparisonBreakdown from './components/origem/OrigemComparisonBreakdown.vue';
import OrigemAgentTable from './components/origem/OrigemAgentTable.vue';
import {
  useOrigemReport,
  PERIOD_OPTIONS,
  AGENT_TYPE_OPTIONS,
} from './composables/useOrigemReport';

const { t } = useI18n();

const teams = useMapGetter('teams/getTeams');

const {
  current,
  loading,
  loaded,
  hasError,
  filters,
  fetch,
  setPeriod,
  setCustomRange,
  setTeam,
  setAgentType,
} = useOrigemReport();

const teamOptions = computed(() => [
  { value: '', label: t('REPORT.ORIGEM.ALL_TEAMS') },
  ...teams.value.map(team => ({ value: team.id, label: team.name })),
]);

const onTeamChange = value => setTeam(value ? Number(value) : null);

const agentTypeLabel = value =>
  t(`REPORT.ORIGEM.AGENT_TYPE.${value.toUpperCase()}`);
const periodLabel = value => t(`REPORT.ORIGEM.PERIOD.${value.toUpperCase()}`);

const onCustomRangeChange = ([start, end]) => {
  if (!start || !end) return;
  setCustomRange([start, end]);
};

fetch();
</script>

<template>
  <section class="flex flex-col w-full gap-4">
    <ReportHeader
      :header-title="t('REPORT.ORIGEM.TITLE')"
      :header-description="t('REPORT.ORIGEM.DESCRIPTION')"
    />

    <div class="flex flex-wrap items-end gap-3">
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('REPORT.ORIGEM.TEAM_FILTER') }}
        <Select
          :model-value="filters.teamId || ''"
          :options="teamOptions"
          @update:model-value="onTeamChange"
        />
      </label>

      <div
        role="group"
        :aria-label="t('REPORT.ORIGEM.AGENT_TYPE.LABEL')"
        class="flex flex-col gap-1"
      >
        <span class="text-sm text-n-slate-11">{{
          t('REPORT.ORIGEM.AGENT_TYPE.LABEL')
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
        :aria-label="t('REPORT.ORIGEM.PERIOD.LABEL')"
        class="flex flex-col gap-1"
      >
        <span class="text-sm text-n-slate-11">{{
          t('REPORT.ORIGEM.PERIOD.LABEL')
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
        {{ t('REPORT.ORIGEM.PERIOD.CUSTOM') }}
        <DateRangePicker
          :value="filters.customRange"
          :confirm-text="t('REPORT.ORIGEM.PERIOD.CUSTOM')"
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
        {{ t('REPORT.ORIGEM.ERROR') }}
      </span>
    </Banner>

    <!-- Trocar filtro mantem os numeros anteriores na tela em vez de piscar
         spinner; a opacidade e a pista de que ha consulta em voo. -->
    <div v-else class="flex flex-col gap-6" :class="{ 'opacity-50': loading }">
      <OrigemSummaryTiles :summary="current.summary" />

      <OrigemDailyEvolutionChart :daily-evolution="current.dailyEvolution" />

      <OrigemBreakdown :items="current.byOrigin" />

      <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <OrigemComparisonBreakdown
          :title="t('REPORT.ORIGEM.TEAM.TITLE')"
          :hint="t('REPORT.ORIGEM.TEAM.HINT')"
          :items="current.byTeam"
          :no-name-label="t('REPORT.ORIGEM.TEAM.NO_TEAM')"
          :empty-label="t('REPORT.ORIGEM.TEAM.EMPTY')"
          :recebidos-label="t('REPORT.ORIGEM.RECEBIDOS')"
          :efetuados-label="t('REPORT.ORIGEM.EFETUADOS')"
          :visible-limit="8"
          :show-all-label="
            t('REPORT.ORIGEM.TEAM.SHOW_ALL', { count: current.byTeam.length })
          "
        />
        <OrigemComparisonBreakdown
          :title="t('REPORT.ORIGEM.INBOX.TITLE')"
          :hint="t('REPORT.ORIGEM.INBOX.HINT')"
          :items="current.byInbox"
          :empty-label="t('REPORT.ORIGEM.INBOX.EMPTY')"
          :recebidos-label="t('REPORT.ORIGEM.RECEBIDOS')"
          :efetuados-label="t('REPORT.ORIGEM.EFETUADOS')"
        />
      </div>

      <OrigemAgentTable :items="current.byAgent" />

      <!-- O criterio precisa estar na tela: "quem atende" e o mesmo recorte ao
           vivo do Monitoramento, nao o classificador por resolucao que Robo e
           humano usa. -->
      <p class="flex items-start gap-2 m-0 text-xs text-n-slate-11">
        <span class="mt-0.5 size-3.5 shrink-0 i-lucide-info" />
        {{ t('REPORT.ORIGEM.CRITERION') }}
      </p>
    </div>
  </section>
</template>
