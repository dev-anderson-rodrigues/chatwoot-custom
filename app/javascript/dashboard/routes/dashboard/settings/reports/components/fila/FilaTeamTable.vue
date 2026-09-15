<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatTime } from '@chatwoot/utils';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';

defineProps({
  items: { type: Array, default: () => [] },
});

const { t } = useI18n();

const formatCount = value => Number(value).toLocaleString();
const formatDuration = seconds => formatTime(seconds ?? 0);

const tableHeaders = computed(() => [
  t('REPORT.FILA.TEAM.TABLE.TEAM'),
  t('REPORT.FILA.TEAM.TABLE.TOTAL'),
  t('REPORT.FILA.TEAM.TABLE.AVG_WAIT'),
  t('REPORT.FILA.TEAM.TABLE.MAX_WAIT'),
  t('REPORT.FILA.TEAM.TABLE.ABANDONED'),
]);
</script>

<template>
  <section class="flex flex-col gap-1">
    <h3 class="m-0 text-sm font-medium text-n-slate-12">
      {{ t('REPORT.FILA.TEAM.TITLE') }}
    </h3>

    <div class="w-full overflow-x-auto">
      <BaseTable
        :headers="tableHeaders"
        :items="items"
        :no-data-message="t('REPORT.FILA.TEAM.EMPTY')"
      >
        <template #row>
          <BaseTableRow
            v-for="row in items"
            :key="row.id ?? 'none'"
            :item="row"
          >
            <BaseTableCell>
              <span class="text-sm text-n-slate-12">{{
                row.name || t('REPORT.FILA.TEAM.NO_TEAM')
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
              <span
                class="text-sm font-medium tabular-nums"
                :class="
                  row.abandoned > 0 ? 'text-n-ruby-11' : 'text-n-slate-11'
                "
              >
                {{ formatCount(row.abandoned) }}
              </span>
            </BaseTableCell>
          </BaseTableRow>
        </template>
      </BaseTable>
    </div>
  </section>
</template>
