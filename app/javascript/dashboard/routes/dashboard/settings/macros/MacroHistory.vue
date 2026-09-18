<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import {
  useMacroExecutions,
  EXECUTION_STATUSES,
  PAGE_SIZE,
} from 'dashboard/composables/useMacroExecutions';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import Button from 'dashboard/components-next/button/Button.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';

const props = defineProps({
  macroId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const store = useStore();

const {
  executions,
  total,
  page,
  loading,
  hasError,
  filters,
  hasActiveFilters,
  clearFilters,
  fetch,
} = useMacroExecutions(props.macroId);

const STATUS_COLORS = {
  pending: 'slate',
  success: 'teal',
  partial: 'amber',
  failed: 'ruby',
};

const agents = useMapGetter('agents/getAgents');
const expandedId = ref(null);

const statusOptions = computed(() => [
  { value: '', label: t('MACROS.HISTORY.FILTER_ALL') },
  ...EXECUTION_STATUSES.map(status => ({
    value: status,
    label: t(`MACROS.HISTORY.STATUS.${status.toUpperCase()}`),
  })),
]);

const agentOptions = computed(() => [
  { value: '', label: t('MACROS.HISTORY.FILTER_ALL') },
  ...agents.value.map(agent => ({
    value: agent.id,
    label: agent.available_name || agent.name,
  })),
]);

const tableHeaders = computed(() => [
  t('MACROS.HISTORY.COL_DATE'),
  t('MACROS.HISTORY.COL_AGENT'),
  t('MACROS.HISTORY.COL_CONVERSATION'),
  t('MACROS.HISTORY.COL_STATUS'),
  t('MACROS.HISTORY.COL_ACTIONS'),
  '',
]);

const toggleExpand = id => {
  expandedId.value = expandedId.value === id ? null : id;
};

const inputEntries = inputs =>
  Object.entries(inputs).map(([key, value]) => ({
    key,
    value: Array.isArray(value) ? value.join(', ') : String(value ?? ''),
  }));

onMounted(() => {
  store.dispatch('agents/get');
  fetch();
});
</script>

<template>
  <section class="flex flex-col gap-4 py-4">
    <header class="flex items-start justify-between gap-4">
      <div class="flex flex-col gap-0.5">
        <h3 class="m-0 text-base font-medium text-n-slate-12">
          {{ t('MACROS.HISTORY.TITLE') }}
        </h3>
        <p class="m-0 text-sm text-n-slate-11">
          {{ t('MACROS.HISTORY.DESCRIPTION') }}
        </p>
      </div>
      <Button
        :label="t('MACROS.HISTORY.REFRESH')"
        icon="i-lucide-refresh-cw"
        slate
        ghost
        sm
        :disabled="loading"
        @click="fetch"
      />
    </header>

    <div
      class="flex flex-wrap items-end gap-4 p-3 border rounded-lg border-n-weak bg-n-alpha-1"
    >
      <!-- Label envolvendo o controle: o `id` passado ao Select pousaria na div
           raiz dele, e um `for` apontando para div nao nomeia campo nenhum. -->
      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('MACROS.HISTORY.FILTER_STATUS') }}
        <Select v-model="filters.status" :options="statusOptions" />
      </label>

      <label class="flex flex-col gap-1 text-sm text-n-slate-11">
        {{ t('MACROS.HISTORY.FILTER_AGENT') }}
        <Select v-model="filters.userId" :options="agentOptions" />
      </label>

      <div class="flex flex-col gap-1">
        <label for="macro-history-from" class="text-sm text-n-slate-11">
          {{ t('MACROS.HISTORY.FILTER_FROM') }}
        </label>
        <input
          id="macro-history-from"
          v-model="filters.from"
          type="date"
          class="px-3 py-2 text-sm border-0 rounded-lg outline outline-1 -outline-offset-1 outline-n-weak bg-n-surface-1 text-n-slate-12 hover:outline-n-slate-6 focus:outline-n-blue-9"
        />
      </div>

      <div class="flex flex-col gap-1">
        <label for="macro-history-to" class="text-sm text-n-slate-11">
          {{ t('MACROS.HISTORY.FILTER_TO') }}
        </label>
        <input
          id="macro-history-to"
          v-model="filters.to"
          type="date"
          class="px-3 py-2 text-sm border-0 rounded-lg outline outline-1 -outline-offset-1 outline-n-weak bg-n-surface-1 text-n-slate-12 hover:outline-n-slate-6 focus:outline-n-blue-9"
        />
      </div>

      <Button
        v-if="hasActiveFilters"
        :label="t('MACROS.HISTORY.CLEAR_FILTERS')"
        icon="i-lucide-x"
        slate
        ghost
        sm
        @click="clearFilters"
      />

      <span class="text-sm ltr:ml-auto rtl:mr-auto text-n-slate-11">
        {{ t('MACROS.HISTORY.TOTAL_COUNT', { count: total }, total) }}
      </span>
    </div>

    <div v-if="loading" class="flex justify-center py-16 text-n-slate-11">
      <Spinner />
    </div>

    <div
      v-else-if="hasError"
      class="flex items-center gap-2 px-4 py-3 text-sm rounded-lg text-n-ruby-11 bg-n-ruby-3"
    >
      <span class="size-4 i-lucide-circle-alert" />
      {{ t('MACROS.HISTORY.ERROR') }}
    </div>

    <div v-else class="flex flex-col">
      <BaseTable
        :headers="tableHeaders"
        :items="executions"
        :no-data-message="t('MACROS.HISTORY.EMPTY')"
      >
        <template #row="{ items }">
          <template v-for="execution in items" :key="execution.id">
            <BaseTableRow :item="execution">
              <template #default>
                <BaseTableCell>
                  <span class="text-sm whitespace-nowrap text-n-slate-12">
                    {{
                      messageTimestamp(
                        execution.createdAt,
                        'MMM dd, yyyy hh:mm a'
                      )
                    }}
                  </span>
                </BaseTableCell>

                <BaseTableCell>
                  <span class="text-sm text-n-slate-12">
                    {{ execution.agentName || '—' }}
                  </span>
                </BaseTableCell>

                <BaseTableCell>
                  <span
                    v-if="execution.conversationDisplayId"
                    class="text-sm text-n-slate-12"
                  >
                    #{{ execution.conversationDisplayId }}
                  </span>
                  <span v-else class="text-sm text-n-slate-10">
                    {{ t('MACROS.HISTORY.NO_CONVERSATION') }}
                  </span>
                </BaseTableCell>

                <BaseTableCell>
                  <Label
                    :label="
                      t(
                        `MACROS.HISTORY.STATUS.${execution.status.toUpperCase()}`
                      )
                    "
                    :color="STATUS_COLORS[execution.status]"
                    compact
                  />
                </BaseTableCell>

                <BaseTableCell>
                  <span class="text-sm whitespace-nowrap text-n-slate-11">
                    {{
                      t('MACROS.HISTORY.ACTIONS_RATIO', {
                        run: execution.actionsRun,
                        total: execution.actionsTotal,
                      })
                    }}
                  </span>
                </BaseTableCell>

                <BaseTableCell class="w-10">
                  <Button
                    :icon="
                      expandedId === execution.id
                        ? 'i-lucide-chevron-up'
                        : 'i-lucide-chevron-down'
                    "
                    :aria-label="
                      expandedId === execution.id
                        ? t('MACROS.HISTORY.COLLAPSE')
                        : t('MACROS.HISTORY.EXPAND')
                    "
                    :aria-expanded="expandedId === execution.id"
                    slate
                    ghost
                    xs
                    @click="toggleExpand(execution.id)"
                  />
                </BaseTableCell>
              </template>
            </BaseTableRow>

            <tr v-if="expandedId === execution.id">
              <td :colspan="tableHeaders.length" class="py-4 bg-n-alpha-1">
                <div class="flex flex-col gap-4 px-1">
                  <div class="flex flex-col gap-2">
                    <h4 class="m-0 text-sm font-medium text-n-slate-12">
                      {{ t('MACROS.HISTORY.INPUTS') }}
                    </h4>
                    <p
                      v-if="!inputEntries(execution.inputs).length"
                      class="m-0 text-sm text-n-slate-10"
                    >
                      {{ t('MACROS.HISTORY.NO_INPUTS') }}
                    </p>
                    <dl v-else class="grid gap-x-6 gap-y-1 sm:grid-cols-2">
                      <div
                        v-for="entry in inputEntries(execution.inputs)"
                        :key="entry.key"
                        class="flex gap-2 text-sm"
                      >
                        <dt class="text-n-slate-11">{{ entry.key }}</dt>
                        <dd class="m-0 font-medium break-all text-n-slate-12">
                          {{ entry.value }}
                        </dd>
                      </div>
                    </dl>
                  </div>

                  <div
                    v-if="execution.errorMessage"
                    class="flex flex-col gap-2"
                  >
                    <h4 class="m-0 text-sm font-medium text-n-ruby-11">
                      {{ t('MACROS.HISTORY.ERROR_MESSAGE') }}
                    </h4>
                    <p
                      class="m-0 text-sm whitespace-pre-wrap break-words text-n-slate-12"
                    >
                      {{ execution.errorMessage }}
                    </p>
                  </div>
                </div>
              </td>
            </tr>
          </template>
        </template>
      </BaseTable>

      <PaginationFooter
        v-if="total > PAGE_SIZE"
        :current-page="page"
        :total-items="total"
        :items-per-page="PAGE_SIZE"
        class="!px-0"
        @update:current-page="page = $event"
      />
    </div>
  </section>
</template>
