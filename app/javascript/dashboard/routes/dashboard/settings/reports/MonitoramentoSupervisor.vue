<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatTime } from '@chatwoot/utils';
import { useMapGetter } from 'dashboard/composables/store';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ReportHeader from './components/ReportHeader.vue';
import ReportTile from './components/ReportTile.vue';
import SupervisorQueueByTeam from './components/supervisor/SupervisorQueueByTeam.vue';
import SupervisorConversationsTable from './components/supervisor/SupervisorConversationsTable.vue';
import SupervisorAgentsPanel from './components/supervisor/SupervisorAgentsPanel.vue';
import SupervisorAlerts from './components/supervisor/SupervisorAlerts.vue';
import {
  useSupervisorReport,
  AGENT_TYPE_OPTIONS,
} from './composables/useSupervisorReport';

const { t } = useI18n();

const teams = useMapGetter('teams/getTeams');

const {
  current,
  loading,
  loaded,
  hasError,
  filters,
  setTeam,
  setAgentType,
  setStatusFilter,
  setPage,
} = useSupervisorReport();

const teamOptions = computed(() => [
  { value: '', label: t('REPORT.SUPERVISOR.ALL_TEAMS') },
  ...teams.value.map(team => ({ value: team.id, label: team.name })),
]);

const onTeamChange = value => setTeam(value ? Number(value) : null);

const agentTypeLabel = value =>
  t(`REPORT.SUPERVISOR.AGENT_TYPE.${value.toUpperCase()}`);

const kpiTiles = computed(() => {
  const kpis = current.value.kpis;

  return [
    {
      key: 'inProgress',
      label: t('REPORT.SUPERVISOR.KPI.IN_PROGRESS'),
      value: kpis.inProgress,
    },
    {
      key: 'inQueue',
      label: t('REPORT.SUPERVISOR.KPI.IN_QUEUE'),
      value: kpis.inQueue,
    },
    {
      key: 'longestWait',
      label: t('REPORT.SUPERVISOR.KPI.LONGEST_WAIT'),
      value: kpis.longestWaitMinutes
        ? formatTime(kpis.longestWaitMinutes * 60)
        : '—',
    },
    {
      key: 'agentsOnline',
      label: t('REPORT.SUPERVISOR.KPI.AGENTS_ONLINE'),
      value: `${kpis.agentsOnline}/${kpis.agentsTotal}`,
    },
    {
      key: 'avgLoad',
      label: t('REPORT.SUPERVISOR.KPI.AVG_LOAD'),
      value: kpis.avgLoad,
    },
  ];
});

// So aparece quando a janela de 30 dias (kpis.longestWaitWindowDays) deixou
// alguma conversa esquecida de fora do calculo do KPI acima.
const staleInQueueNote = computed(() => {
  const kpis = current.value.kpis;
  if (!kpis.staleInQueue) return null;

  return t('REPORT.SUPERVISOR.KPI.STALE_IN_QUEUE', {
    count: kpis.staleInQueue,
    days: kpis.longestWaitWindowDays,
  });
});
</script>

<template>
  <section class="flex flex-col w-full gap-4">
    <ReportHeader
      :header-title="t('REPORT.SUPERVISOR.TITLE')"
      :header-description="t('REPORT.SUPERVISOR.DESCRIPTION')"
    />

    <div class="flex flex-wrap items-end gap-3">
      <!-- Label envolvendo o controle: a raiz do Select e uma div, entao um
           `for` apontando para o id dele nao nomearia campo nenhum -- mesmo
           padrao do Cockpit. -->
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('REPORT.SUPERVISOR.TEAM_FILTER') }}
        <Select
          :model-value="filters.teamId || ''"
          :options="teamOptions"
          @update:model-value="onTeamChange"
        />
      </label>

      <div
        role="group"
        :aria-label="t('REPORT.SUPERVISOR.AGENT_TYPE.LABEL')"
        class="flex flex-col gap-1"
      >
        <span class="text-sm text-n-slate-11">
          {{ t('REPORT.SUPERVISOR.AGENT_TYPE.LABEL') }}
        </span>
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

      <div class="flex items-center gap-2 ml-auto text-xs text-n-slate-10">
        <span
          class="size-3.5 i-lucide-refresh-cw"
          :class="{ 'animate-spin': loading }"
        />
        {{ t('REPORT.SUPERVISOR.AUTO_REFRESH') }}
      </div>
    </div>

    <div v-if="loading && !loaded" class="flex justify-center py-10">
      <Spinner />
    </div>

    <Banner v-else-if="hasError" color="ruby">
      <span class="flex items-center gap-2">
        <span class="size-4 i-lucide-circle-alert" />
        {{ t('REPORT.SUPERVISOR.ERROR') }}
      </span>
    </Banner>

    <!-- Trocar filtro ou atualizar sozinho mantem os numeros anteriores na
         tela em vez de piscar um spinner; a opacidade e a pista de que ha
         consulta em voo. -->
    <div
      v-else
      class="flex flex-col gap-6"
      :class="{ 'opacity-50': loading && loaded }"
    >
      <div class="flex flex-col gap-1">
        <dl class="grid grid-cols-2 gap-3 m-0 sm:grid-cols-3 xl:grid-cols-5">
          <ReportTile
            v-for="tile in kpiTiles"
            :key="tile.key"
            :label="tile.label"
            :value="tile.value"
          />
        </dl>
        <p v-if="staleInQueueNote" class="m-0 text-xs text-n-slate-10">
          {{ staleInQueueNote }}
        </p>
      </div>

      <SupervisorQueueByTeam :teams="current.queueByTeam" />

      <SupervisorConversationsTable
        :items="current.conversations.items"
        :counts="current.conversations.counts"
        :pagination="current.conversations.pagination"
        :status-filter="filters.statusFilter"
        @update:status-filter="setStatusFilter"
        @update:page="setPage"
      />

      <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <SupervisorAgentsPanel :agents="current.agents" />
        <SupervisorAlerts :alerts="current.alerts" />
      </div>

      <!-- O criterio precisa estar na tela: "quem atende" e estado atual, nao
           o classificador por resolucao que as telas de Robo e humano usam. -->
      <p class="flex items-start gap-2 m-0 text-xs text-n-slate-11">
        <span class="mt-0.5 size-3.5 shrink-0 i-lucide-info" />
        {{ t('REPORT.SUPERVISOR.CRITERION') }}
      </p>
    </div>
  </section>
</template>
