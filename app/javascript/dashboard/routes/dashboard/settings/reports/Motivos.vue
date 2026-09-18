<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import DateRangePicker from 'dashboard/components/ui/DateRangePicker.vue';
import ReportHeader from './components/ReportHeader.vue';
import MotivosLabelPicker from './components/motivos/MotivosLabelPicker.vue';
import MotivosKpiTiles from './components/motivos/MotivosKpiTiles.vue';
import MotivosWeeklyChart from './components/motivos/MotivosWeeklyChart.vue';
import MotivosTable from './components/motivos/MotivosTable.vue';
import {
  useMotivosReport,
  PERIOD_OPTIONS,
  AGENT_TYPE_OPTIONS,
  DATE_FIELD_OPTIONS,
} from './composables/useMotivosReport';

const { t } = useI18n();
const store = useStore();

const teams = useMapGetter('teams/getTeams');
const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabels');

const {
  report,
  loading,
  loaded,
  hasError,
  needsSelection,
  filters,
  trendOf,
  fetch,
  setPeriod,
  setCustomRange,
  setTeam,
  setInbox,
  setDateField,
  setLabels,
  setAgentType,
} = useMotivosReport();

const teamOptions = computed(() => [
  { value: '', label: t('REPORT.MOTIVOS.ALL_TEAMS') },
  ...teams.value.map(team => ({ value: team.id, label: team.name })),
]);

const inboxOptions = computed(() => [
  { value: '', label: t('REPORT.MOTIVOS.ALL_INBOXES') },
  ...inboxes.value.map(inbox => ({ value: inbox.id, label: inbox.name })),
]);

const onTeamChange = value => setTeam(value ? Number(value) : null);
const onInboxChange = value => setInbox(value ? Number(value) : null);

const agentTypeLabel = value =>
  t(`REPORT.MOTIVOS.AGENT_TYPE.${value.toUpperCase()}`);
const periodLabel = value => t(`REPORT.MOTIVOS.PERIOD.${value.toUpperCase()}`);
const dateFieldLabel = value =>
  t(`REPORT.MOTIVOS.DATE_FIELD.${value.toUpperCase()}`);

const onCustomRangeChange = ([start, end]) => {
  if (!start || !end) return;
  setCustomRange([start, end]);
};

// As etiquetas vem do store, nao da resposta do relatorio: o usuario precisa
// ver o que PODE escolher antes de haver relatorio nenhum.
onMounted(() => {
  store.dispatch('labels/get');
  fetch();
});
</script>

<template>
  <section class="flex flex-col w-full gap-4">
    <ReportHeader
      :header-title="t('REPORT.MOTIVOS.TITLE')"
      :header-description="t('REPORT.MOTIVOS.DESCRIPTION')"
    />

    <MotivosLabelPicker
      :available-labels="labels"
      :selected="filters.labels"
      @update="setLabels"
    />

    <div class="flex flex-wrap items-end gap-3">
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('REPORT.MOTIVOS.TEAM_FILTER') }}
        <Select
          :model-value="filters.teamId || ''"
          :options="teamOptions"
          @update:model-value="onTeamChange"
        />
      </label>

      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('REPORT.MOTIVOS.INBOX_FILTER') }}
        <Select
          :model-value="filters.inboxId || ''"
          :options="inboxOptions"
          @update:model-value="onInboxChange"
        />
      </label>

      <div
        role="group"
        :aria-label="t('REPORT.MOTIVOS.AGENT_TYPE.LABEL')"
        class="flex flex-col gap-1"
      >
        <span class="text-sm text-n-slate-11">{{
          t('REPORT.MOTIVOS.AGENT_TYPE.LABEL')
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
        :aria-label="t('REPORT.MOTIVOS.DATE_FIELD.LABEL')"
        class="flex flex-col gap-1"
      >
        <span class="text-sm text-n-slate-11">{{
          t('REPORT.MOTIVOS.DATE_FIELD.LABEL')
        }}</span>
        <div class="flex items-center gap-1">
          <Button
            v-for="option in DATE_FIELD_OPTIONS"
            :key="option"
            :label="dateFieldLabel(option)"
            :variant="filters.dateField === option ? 'solid' : 'ghost'"
            :color="filters.dateField === option ? 'blue' : 'slate'"
            :aria-pressed="filters.dateField === option"
            size="sm"
            @click="setDateField(option)"
          />
        </div>
      </div>

      <div
        role="group"
        :aria-label="t('REPORT.MOTIVOS.PERIOD.LABEL')"
        class="flex flex-col gap-1"
      >
        <span class="text-sm text-n-slate-11">{{
          t('REPORT.MOTIVOS.PERIOD.LABEL')
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
        {{ t('REPORT.MOTIVOS.PERIOD.CUSTOM') }}
        <DateRangePicker
          :value="filters.customRange"
          :confirm-text="t('REPORT.MOTIVOS.PERIOD.CUSTOM')"
          @change="onCustomRangeChange"
        />
      </label>
    </div>

    <!-- Estado de configuracao, nao de vazio: a tela nao tem pergunta a fazer
         antes de o usuario dizer quais etiquetas significam motivo. -->
    <div
      v-if="needsSelection"
      class="flex flex-col items-center gap-2 px-6 py-12 text-center border border-dashed rounded-lg border-n-weak"
    >
      <span class="size-6 text-n-slate-10 i-lucide-tags" />
      <p class="m-0 text-sm font-medium text-n-slate-12">
        {{ t('REPORT.MOTIVOS.NEEDS_SELECTION.TITLE') }}
      </p>
      <p class="max-w-md m-0 text-sm text-n-slate-11">
        {{ t('REPORT.MOTIVOS.NEEDS_SELECTION.DESCRIPTION') }}
      </p>
    </div>

    <div v-else-if="loading && !loaded" class="flex justify-center py-10">
      <Spinner />
    </div>

    <Banner v-else-if="hasError" color="ruby">
      <span class="flex items-center gap-2">
        <span class="size-4 i-lucide-circle-alert" />
        {{ t('REPORT.MOTIVOS.ERROR') }}
      </span>
    </Banner>

    <!-- Trocar filtro mantem os numeros anteriores na tela em vez de piscar
         spinner; a opacidade e a pista de que ha consulta em voo. -->
    <div v-else class="flex flex-col gap-6" :class="{ 'opacity-50': loading }">
      <MotivosKpiTiles :kpis="report.kpis" />

      <MotivosWeeklyChart :evolution="report.weeklyEvolution" />

      <MotivosTable :items="report.reasons" :trend-of="trendOf" />

      <!-- O criterio precisa estar na tela: FCR e por historico da conversa (nao
           da janela), participacao do robo usa o mesmo classificador das outras
           telas da onda, e motivo que zerou continua listado para a queda ficar
           visivel. -->
      <p class="flex items-start gap-2 m-0 text-xs text-n-slate-11">
        <span class="mt-0.5 size-3.5 shrink-0 i-lucide-info" />
        {{ t('REPORT.MOTIVOS.CRITERION') }}
      </p>
    </div>
  </section>
</template>
