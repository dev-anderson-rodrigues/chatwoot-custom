<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';

const props = defineProps({
  items: { type: Array, default: () => [] },
});

const VISIBLE_LIMIT = 15;

const { t } = useI18n();

const showAll = ref(false);

const visibleItems = computed(() =>
  showAll.value ? props.items : props.items.slice(0, VISIBLE_LIMIT)
);

const hasMore = computed(() => props.items.length > VISIBLE_LIMIT);

const formatCount = value => Number(value).toLocaleString();

const tableHeaders = computed(() => [
  t('REPORT.ORIGEM.AGENT.TABLE.AGENT'),
  t('REPORT.ORIGEM.AGENT.TABLE.RECEBIDOS'),
  t('REPORT.ORIGEM.AGENT.TABLE.EFETUADOS'),
  t('REPORT.ORIGEM.AGENT.TABLE.TOTAL'),
]);
</script>

<template>
  <section class="flex flex-col gap-1">
    <h3 class="m-0 text-sm font-medium text-n-slate-12">
      {{ t('REPORT.ORIGEM.AGENT.TITLE') }}
    </h3>
    <p class="m-0 mb-2 text-xs text-n-slate-10">
      {{ t('REPORT.ORIGEM.AGENT.DESCRIPTION') }}
    </p>

    <div class="w-full overflow-x-auto">
      <BaseTable
        :headers="tableHeaders"
        :items="items"
        :no-data-message="t('REPORT.ORIGEM.AGENT.EMPTY')"
      >
        <template #row>
          <BaseTableRow
            v-for="row in visibleItems"
            :key="row.id ?? 'none'"
            :item="row"
          >
            <BaseTableCell>
              <span class="text-sm text-n-slate-12">{{
                row.name || t('REPORT.ORIGEM.AGENT.NO_AGENT')
              }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-sm font-medium tabular-nums text-n-blue-11">{{
                formatCount(row.recebidos)
              }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-sm font-medium tabular-nums text-n-amber-11">{{
                formatCount(row.efetuados)
              }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-sm font-bold tabular-nums text-n-slate-12">{{
                formatCount(row.total)
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
            ? t('REPORT.ORIGEM.AGENT.SHOW_LESS')
            : t('REPORT.ORIGEM.AGENT.SHOW_ALL', { count: items.length })
        }}
      </button>
    </div>
  </section>
</template>
