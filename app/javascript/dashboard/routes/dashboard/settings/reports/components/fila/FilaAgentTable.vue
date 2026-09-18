<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatTime } from '@chatwoot/utils';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';

const props = defineProps({
  items: { type: Array, default: () => [] },
  botHint: { type: Boolean, default: false },
});

const VISIBLE_LIMIT = 10;

const { t } = useI18n();

const showAll = ref(false);

const visibleItems = computed(() =>
  showAll.value ? props.items : props.items.slice(0, VISIBLE_LIMIT)
);

const hasMore = computed(() => props.items.length > VISIBLE_LIMIT);

const formatCount = value => Number(value).toLocaleString();
const formatDuration = seconds => formatTime(seconds ?? 0);
const formatLoadPct = value => `${value}%`;

const tableHeaders = computed(() => [
  t('REPORT.FILA.AGENT.TABLE.AGENT'),
  t('REPORT.FILA.AGENT.TABLE.TOTAL'),
  t('REPORT.FILA.AGENT.TABLE.AVG_WAIT'),
  t('REPORT.FILA.AGENT.TABLE.MAX_WAIT'),
  t('REPORT.FILA.AGENT.TABLE.LOAD_PCT'),
]);
</script>

<template>
  <section class="flex flex-col gap-1">
    <h3 class="m-0 text-sm font-medium text-n-slate-12">
      {{ t('REPORT.FILA.AGENT.TITLE') }}
    </h3>
    <p class="m-0 mb-2 text-xs text-n-slate-10">
      {{ t('REPORT.FILA.AGENT.DESCRIPTION') }}
    </p>
    <p v-if="botHint" class="m-0 mb-2 -mt-2 text-xs text-n-slate-10">
      {{ t('REPORT.FILA.AGENT.BOT_HINT') }}
    </p>

    <div class="w-full overflow-x-auto">
      <BaseTable
        :headers="tableHeaders"
        :items="items"
        :no-data-message="t('REPORT.FILA.AGENT.EMPTY')"
      >
        <template #row>
          <BaseTableRow
            v-for="row in visibleItems"
            :key="row.id ?? 'none'"
            :item="row"
          >
            <BaseTableCell>
              <span class="text-sm text-n-slate-12">{{
                row.name || t('REPORT.FILA.AGENT.NO_AGENT')
              }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-sm font-medium tabular-nums text-n-slate-12">{{
                formatCount(row.total)
              }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-sm tabular-nums text-n-slate-11">{{
                formatDuration(row.avgWaitSeconds)
              }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-sm tabular-nums text-n-slate-11">{{
                formatDuration(row.maxWaitSeconds)
              }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-sm font-medium tabular-nums text-n-slate-12">{{
                formatLoadPct(row.loadPct)
              }}</span>
            </BaseTableCell>
          </BaseTableRow>
        </template>
      </BaseTable>
    </div>

    <div v-if="hasMore" class="flex items-center justify-between mt-1">
      <span class="text-xs text-n-slate-10">
        {{ visibleItems.length }} / {{ items.length }}
      </span>
      <button
        type="button"
        class="text-xs underline text-n-slate-11 hover:text-n-slate-12"
        @click="showAll = !showAll"
      >
        {{
          showAll
            ? t('REPORT.FILA.AGENT.SHOW_LESS')
            : t('REPORT.FILA.AGENT.SHOW_ALL', { count: items.length })
        }}
      </button>
    </div>
  </section>
</template>
