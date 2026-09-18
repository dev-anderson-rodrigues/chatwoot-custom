<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatTime } from '@chatwoot/utils';
import { useMapGetter } from 'dashboard/composables/store';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import ReportHeader from './components/ReportHeader.vue';
import ReportTile from './components/ReportTile.vue';
import {
  useCockpitReport,
  PERIOD_OPTIONS,
  STATUS_OPTIONS,
  DATE_FIELDS,
} from './composables/useCockpitReport';

const { t } = useI18n();
const teams = useMapGetter('teams/getTeams');

const {
  agents,
  totals,
  loading,
  hasError,
  filters,
  isEmpty,
  fetch,
  setPeriod,
  setDateField,
  setTeam,
  setStatus,
  setSearch,
  clearSearch,
} = useCockpitReport();

const STATUS_COLORS = { online: 'teal', busy: 'amber', offline: 'slate' };

const teamOptions = computed(() => [
  { value: null, label: t('REPORT.COCKPIT.TEAM.ALL') },
  ...teams.value.map(team => ({ value: team.id, label: team.name })),
]);

const statusOptions = computed(() => [
  { value: null, label: t('REPORT.COCKPIT.STATUS.ALL') },
  ...STATUS_OPTIONS.map(status => ({
    value: status,
    label: t(`REPORT.COCKPIT.STATUS.${status.toUpperCase()}`),
  })),
]);

const dateFieldOptions = computed(() =>
  DATE_FIELDS.map(field => ({
    value: field,
    label: t(`REPORT.COCKPIT.DATE_FIELD.${field.toUpperCase()}`),
  }))
);

// A cor reforca o rotulo, nunca o substitui: o status vai escrito na pilula.
const statusLabel = status =>
  t(`REPORT.COCKPIT.STATUS.${(status || 'offline').toUpperCase()}`);

const formatDuration = seconds => (seconds ? formatTime(seconds) : '—');

const formatCsat = row =>
  row.csatResponses > 0 ? `${row.csat}` : t('REPORT.COCKPIT.TABLE.NO_CSAT');

const tiles = computed(() => [
  {
    key: 'agents',
    label: t('REPORT.COCKPIT.KPI.AGENTS'),
    value: totals.value.agentsTotal,
  },
  {
    key: 'online',
    label: t('REPORT.COCKPIT.KPI.ONLINE'),
    value: totals.value.agentsOnline,
  },
  {
    key: 'conversations',
    label: t('REPORT.COCKPIT.KPI.CONVERSATIONS'),
    value: totals.value.conversationsTotal,
  },
  {
    key: 'handle',
    label: t('REPORT.COCKPIT.KPI.AVG_HANDLE'),
    value: formatDuration(totals.value.avgHandleSeconds),
  },
  {
    key: 'csat',
    label: t('REPORT.COCKPIT.KPI.AVG_CSAT'),
    value: totals.value.avgCsat ? `${totals.value.avgCsat}` : '—',
  },
]);

const tableHeaders = computed(() =>
  [
    'RANK',
    'AGENT',
    'TEAM',
    'STATUS',
    'CONVERSATIONS',
    'RESOLUTIONS',
    'AVG_HANDLE',
    'FIRST_RESPONSE',
    'REPLY_TIME',
    'CSAT',
  ].map(key => t(`REPORT.COCKPIT.TABLE.${key}`))
);

onMounted(fetch);
</script>

<template>
  <section class="flex flex-col w-full gap-4">
    <!-- Cabecalho do design system, nao um h2 proprio: e ele que traz o
         respiro do topo (pt-6) e a tipografia que as outras telas de relatorio
         usam. Sem ele o titulo encostava na borda superior. -->
    <ReportHeader
      :header-title="t('REPORT.COCKPIT.TITLE')"
      :header-description="t('REPORT.COCKPIT.DESCRIPTION')"
    />

    <div class="flex flex-wrap items-end gap-3">
      <div
        role="group"
        :aria-label="t('REPORT.COCKPIT.PERIOD.LABEL')"
        class="flex items-center gap-1"
      >
        <Button
          v-for="option in PERIOD_OPTIONS"
          :key="option"
          :label="t(`REPORT.COCKPIT.PERIOD.${option.toUpperCase()}`)"
          :variant="filters.period === option ? 'solid' : 'ghost'"
          :color="filters.period === option ? 'blue' : 'slate'"
          :aria-pressed="filters.period === option"
          size="sm"
          @click="setPeriod(option)"
        />
      </div>

      <!-- Label envolvendo o controle: a raiz do Select e uma div, entao um
           `for` apontando para o id dele nao nomearia campo nenhum. -->
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('REPORT.COCKPIT.DATE_FIELD.LABEL') }}
        <Select
          :model-value="filters.dateField"
          :options="dateFieldOptions"
          @update:model-value="setDateField"
        />
      </label>

      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('REPORT.COCKPIT.TEAM.LABEL') }}
        <Select
          :model-value="filters.teamId"
          :options="teamOptions"
          @update:model-value="setTeam"
        />
      </label>

      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('REPORT.COCKPIT.STATUS.LABEL') }}
        <Select
          :model-value="filters.status"
          :options="statusOptions"
          @update:model-value="setStatus"
        />
      </label>

      <!-- Mesma estrutura dos filtros ao lado (label envolvendo o controle):
           com um involucro diferente o campo ficava mais alto que os selects,
           e o items-end da linha nao alinhava. -->
      <div class="flex items-end gap-1">
        <label class="flex flex-col gap-1 text-sm text-n-slate-11">
          {{ t('REPORT.COCKPIT.SEARCH_LABEL') }}
          <input
            :value="filters.search"
            type="search"
            class="px-3 py-2 text-sm border-0 rounded-lg outline outline-1 -outline-offset-1 outline-n-weak bg-n-surface-1 text-n-slate-12 hover:outline-n-slate-6 focus:outline-n-blue-9"
            :placeholder="t('REPORT.COCKPIT.SEARCH_PLACEHOLDER')"
            @input="setSearch($event.target.value)"
          />
        </label>
        <Button
          v-if="filters.search"
          :label="t('REPORT.COCKPIT.CLEAR_SEARCH')"
          variant="ghost"
          color="slate"
          size="sm"
          @click="clearSearch"
        />
      </div>
    </div>

    <div v-if="loading && isEmpty" class="flex justify-center py-10">
      <Spinner />
    </div>

    <Banner v-else-if="hasError" color="ruby">
      <span class="flex items-center gap-2">
        <span class="size-4 i-lucide-circle-alert" />
        {{ t('REPORT.COCKPIT.ERROR') }}
      </span>
    </Banner>

    <!-- Trocar filtro mantem os numeros anteriores na tela em vez de piscar um
         spinner; a opacidade e a pista de que ha consulta em voo. -->
    <div v-else class="flex flex-col gap-4" :class="{ 'opacity-50': loading }">
      <dl class="grid grid-cols-2 gap-3 m-0 sm:grid-cols-3 xl:grid-cols-5">
        <ReportTile
          v-for="tile in tiles"
          :key="tile.key"
          :label="tile.label"
          :value="tile.value"
        />
      </dl>

      <!-- Contêiner de rolagem proprio: o BaseTable e uma div `w-full` sem
           overflow, entao com 10 colunas as tres ultimas ficavam inalcancaveis
           em tela estreita -- confirmado renderizado em 768px, onde a tabela
           media 832px dentro de um espaco de 520px. Rolar aqui mantem filtros e
           KPIs parados; sem isto quem rolava era o painel inteiro. -->
      <div class="w-full overflow-x-auto">
        <BaseTable
          :headers="tableHeaders"
          :items="agents"
          :no-data-message="t('REPORT.COCKPIT.EMPTY')"
        >
          <template #row="{ items }">
            <BaseTableRow v-for="agent in items" :key="agent.id" :item="agent">
              <BaseTableCell>
                <span class="text-sm tabular-nums text-n-slate-11">
                  {{ agent.rank }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <div class="flex flex-col min-w-0">
                  <span class="text-sm truncate text-n-slate-12">
                    {{ agent.name }}
                  </span>
                  <span class="text-xs truncate text-n-slate-11">
                    {{ agent.email }}
                  </span>
                </div>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-sm text-n-slate-11">
                  {{ agent.teamName || t('REPORT.COCKPIT.TABLE.NO_TEAM') }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <Label
                  :label="statusLabel(agent.status)"
                  :color="STATUS_COLORS[agent.status] || 'slate'"
                  size="small"
                />
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-sm tabular-nums text-n-slate-12">
                  {{ agent.conversations }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-sm tabular-nums text-n-slate-12">
                  {{ agent.resolutions }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-sm tabular-nums text-n-slate-11">
                  {{ formatDuration(agent.avgHandleSeconds) }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-sm tabular-nums text-n-slate-11">
                  {{ formatDuration(agent.avgFirstResponseSeconds) }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-sm tabular-nums text-n-slate-11">
                  {{ formatDuration(agent.avgReplySeconds) }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-sm tabular-nums text-n-slate-12">
                  {{ formatCsat(agent) }}
                </span>
              </BaseTableCell>
            </BaseTableRow>
          </template>
        </BaseTable>
      </div>
    </div>
  </section>
</template>
