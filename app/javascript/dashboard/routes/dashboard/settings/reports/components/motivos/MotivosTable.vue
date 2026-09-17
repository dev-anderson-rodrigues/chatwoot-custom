<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatTime } from '@chatwoot/utils';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';

const props = defineProps({
  items: { type: Array, default: () => [] },
  // Recebe a linha e devolve a variacao em pontos percentuais, ou null quando
  // nao havia base de comparacao (ver `trendOf` no composable).
  trendOf: { type: Function, required: true },
});

const { t } = useI18n();

const formatCount = value => Number(value).toLocaleString();
const formatDuration = seconds => formatTime(seconds ?? 0);
// O `%` entra pela interpolacao, nao solto no template: texto cru em template
// e o que o `no-raw-text` do i18n barra.
const formatPct = value => `${value}%`;

// Etiqueta apagada da conta depois de usada chega sem cor -- neutra, em vez de
// inventar uma que o usuario nunca escolheu.
const NEUTRAL_COLOR = 'rgb(var(--slate-8))';
const colorOf = row => row.color || NEUTRAL_COLOR;

const tableHeaders = computed(() => [
  t('REPORT.MOTIVOS.TABLE.REASON'),
  t('REPORT.MOTIVOS.TABLE.TOTAL'),
  t('REPORT.MOTIVOS.TABLE.SHARE'),
  t('REPORT.MOTIVOS.TABLE.TREND'),
  t('REPORT.MOTIVOS.TABLE.AVG_HANDLE'),
  t('REPORT.MOTIVOS.TABLE.RESOLVED'),
  t('REPORT.MOTIVOS.TABLE.FCR'),
  t('REPORT.MOTIVOS.TABLE.BOT_RESOLVED'),
  t('REPORT.MOTIVOS.TABLE.BOT_HANDOFF'),
]);

const trendText = row => {
  const trend = props.trendOf(row);
  if (trend === null) {
    // Motivo que nao existia no periodo anterior: "+100%" seria invencao.
    return row.total > 0 ? t('REPORT.MOTIVOS.TABLE.TREND_NEW') : '—';
  }

  return `${trend > 0 ? '+' : ''}${trend}%`;
};

const trendClass = row => {
  const trend = props.trendOf(row);
  // Neutro de proposito: mais conversas de um motivo nao e bom nem ruim sem
  // saber qual motivo -- pintar de verde ou vermelho seria opiniao.
  if (trend === null || trend === 0) return 'text-n-slate-11';

  return 'text-n-slate-12';
};

// Motivo que zerou no periodo mas existia antes continua na tabela (para a
// queda ficar visivel); esmaecido, porque nao tem numero proprio.
const rowClass = row => (row.total > 0 ? '' : 'opacity-60');

const EMPTY_CELL = '—';

const fcrText = row =>
  row.fcrPct === null
    ? EMPTY_CELL
    : `${row.fcrPct}% (${formatCount(row.fcrCount)})`;

// Motivo que zerou no periodo nao tem TMA nem participacao: mostrar "0 Sec" e
// "0%" ali sugere medida real onde nao houve conversa nenhuma. Achado da
// verificacao visual -- o FCR ja fazia isso, as outras tres colunas nao.
const durationText = row =>
  row.total > 0 ? formatDuration(row.avgHandleSeconds) : EMPTY_CELL;

const shareText = row => (row.total > 0 ? formatPct(row.pct) : EMPTY_CELL);

const botText = row =>
  row.resolvedCount > 0 ? formatPct(row.botResolvedPct) : EMPTY_CELL;

const handoffText = row =>
  row.total > 0 ? formatPct(row.botHandoffPct) : EMPTY_CELL;
</script>

<template>
  <section class="flex flex-col gap-1">
    <h3 class="m-0 text-sm font-medium text-n-slate-12">
      {{ t('REPORT.MOTIVOS.TABLE.TITLE') }}
    </h3>

    <div class="w-full overflow-x-auto">
      <BaseTable
        :headers="tableHeaders"
        :items="items"
        :no-data-message="t('REPORT.MOTIVOS.TABLE.EMPTY')"
      >
        <template #row>
          <BaseTableRow
            v-for="row in items"
            :key="row.name"
            :item="row"
            :class="rowClass(row)"
          >
            <BaseTableCell>
              <span class="flex items-center gap-2">
                <span
                  class="rounded-full size-2.5 shrink-0"
                  :style="{ backgroundColor: colorOf(row) }"
                  aria-hidden="true"
                />
                <span class="text-sm text-n-slate-12">{{ row.name }}</span>
              </span>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-sm font-medium tabular-nums text-n-slate-12">{{
                formatCount(row.total)
              }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-sm tabular-nums text-n-slate-11">{{
                shareText(row)
              }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <span
                class="text-sm tabular-nums"
                :class="trendClass(row)"
                :title="
                  t('REPORT.MOTIVOS.TABLE.TREND_TITLE', {
                    count: formatCount(row.previousTotal),
                  })
                "
              >
                {{ trendText(row) }}
              </span>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-sm tabular-nums text-n-slate-11">{{
                durationText(row)
              }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-sm tabular-nums text-n-slate-11">{{
                formatCount(row.resolvedCount)
              }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-sm tabular-nums text-n-slate-11">{{
                fcrText(row)
              }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-sm tabular-nums text-n-slate-11">{{
                botText(row)
              }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <span class="text-sm tabular-nums text-n-slate-11">{{
                handoffText(row)
              }}</span>
            </BaseTableCell>
          </BaseTableRow>
        </template>
      </BaseTable>
    </div>
  </section>
</template>
