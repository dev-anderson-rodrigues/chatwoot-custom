<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatTime } from '@chatwoot/utils';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import { STATUS_FILTER_OPTIONS } from '../../composables/useSupervisorReport';

const props = defineProps({
  items: { type: Array, default: () => [] },
  counts: {
    type: Object,
    default: () => ({ all: 0, naFila: 0, atendendo: 0, aguardando: 0 }),
  },
  pagination: {
    type: Object,
    default: () => ({ page: 1, perPage: 25, totalCount: 0, totalPages: 0 }),
  },
  statusFilter: { type: String, default: 'all' },
});

const emit = defineEmits(['update:statusFilter', 'update:page']);

const { t } = useI18n();

// na_fila = sem agente | atendendo = com agente e respondida | aguardando = pendente/sem resposta
const STATUS_COLORS = {
  na_fila: 'slate',
  atendendo: 'teal',
  aguardando: 'amber',
};
const COUNT_KEY_BY_STATUS_FILTER = {
  all: 'all',
  na_fila: 'naFila',
  atendendo: 'atendendo',
  aguardando: 'aguardando',
};

const statusFilterLabel = value =>
  t(`REPORT.SUPERVISOR.TABLE.STATUS_FILTER.${value.toUpperCase()}`);

const tabs = computed(() =>
  STATUS_FILTER_OPTIONS.map(value => ({
    value,
    label: statusFilterLabel(value),
    count: props.counts[COUNT_KEY_BY_STATUS_FILTER[value]],
  }))
);

const activeTabIndex = computed(() =>
  Math.max(STATUS_FILTER_OPTIONS.indexOf(props.statusFilter), 0)
);

const onTabChanged = tab => emit('update:statusFilter', tab.value);
const onPageChanged = page => emit('update:page', page);

const agentLabel = row =>
  row.agentName || t('REPORT.SUPERVISOR.TABLE.NO_AGENT');
// Minutos crus viravam numero de 5 digitos numa conversa esquecida ha
// semanas ("64825min"); formatTime escala para hora/dia como o resto das
// telas de relatorio ja faz com duracao.
const durationLabel = minutes => (minutes ? formatTime(minutes * 60) : '—');

const tableHeaders = computed(() => [
  t('REPORT.SUPERVISOR.TABLE.STATUS'),
  t('REPORT.SUPERVISOR.TABLE.CONTACT'),
  t('REPORT.SUPERVISOR.TABLE.AGENT'),
  t('REPORT.SUPERVISOR.TABLE.INBOX'),
  '',
  t('REPORT.SUPERVISOR.TABLE.DURATION'),
  t('REPORT.SUPERVISOR.TABLE.LAST_MESSAGE'),
]);
</script>

<template>
  <section class="flex flex-col gap-2">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <h3 class="m-0 text-sm font-medium text-n-slate-12">
        {{ t('REPORT.SUPERVISOR.TABLE.TITLE') }}
      </h3>
      <!-- TabBar e `w-fit`, sem quebra interna entre os chips: com os quatro
           label+contagem (ex. "Em atendimento (3)") ela passa da largura da
           tela em 375px e empurrava a PAGINA inteira para rolar na
           horizontal -- achado renderizado. Rolagem propria aqui, mesmo
           padrao do container da tabela logo abaixo. -->
      <div class="w-full overflow-x-auto sm:w-auto">
        <TabBar
          :tabs="tabs"
          :initial-active-tab="activeTabIndex"
          @tab-changed="onTabChanged"
        />
      </div>
    </div>

    <!-- Contêiner de rolagem proprio: o BaseTable e uma div `w-full` sem
         overflow, mesmo problema documentado no Cockpit em tela estreita. -->
    <div class="w-full overflow-x-auto">
      <BaseTable
        :headers="tableHeaders"
        :items="items"
        :no-data-message="t('REPORT.SUPERVISOR.TABLE.EMPTY')"
      >
        <template #row="{ items: rows }">
          <BaseTableRow v-for="row in rows" :key="row.id" :item="row">
            <BaseTableCell>
              <Label
                :label="statusFilterLabel(row.status)"
                :color="STATUS_COLORS[row.status]"
                compact
              />
            </BaseTableCell>
            <BaseTableCell>
              <div class="flex flex-col min-w-0">
                <span class="text-sm truncate text-n-slate-12">
                  {{ row.contactName || '—' }}
                </span>
                <span
                  v-if="row.contactPhone"
                  class="text-xs truncate text-n-slate-11"
                >
                  {{ row.contactPhone }}
                </span>
              </div>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-sm truncate text-n-slate-11">{{
                agentLabel(row)
              }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-sm truncate text-n-slate-11">{{
                row.inboxName
              }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <CardPriorityIcon v-if="row.priority" :priority="row.priority" />
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-sm tabular-nums text-n-slate-11">
                {{ durationLabel(row.durationMinutes) }}
              </span>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-sm tabular-nums text-n-slate-11">
                {{ durationLabel(row.lastMessageMinutes) }}
              </span>
            </BaseTableCell>
          </BaseTableRow>
        </template>
      </BaseTable>
    </div>

    <PaginationFooter
      v-if="pagination.totalCount > pagination.perPage"
      :current-page="pagination.page"
      :total-items="pagination.totalCount"
      :items-per-page="pagination.perPage"
      class="!px-0"
      @update:current-page="onPageChanged"
    />
  </section>
</template>
