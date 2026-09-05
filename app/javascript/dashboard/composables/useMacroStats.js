import { computed, ref, watch } from 'vue';
import MacrosAPI from 'dashboard/api/macros';

export const PERIOD_OPTIONS = [7, 30, 90];

export const RANKING_SIZE = 5;

const normalize = row => ({
  macroId: row.macro_id,
  name: row.macro_name,
  total: row.total ?? 0,
  counts: {
    pending: row.counts?.pending ?? 0,
    success: row.counts?.success ?? 0,
    partial: row.counts?.partial ?? 0,
    failed: row.counts?.failed ?? 0,
  },
  successRate: row.success_rate ?? null,
  lastExecutedAt: row.last_executed_at ?? null,
});

const daysAgoIso = days => {
  const date = new Date();
  date.setDate(date.getDate() - days);
  return date.toISOString();
};

/**
 * [Fatia 7] Metricas agregadas das macros visiveis ao usuario, servidas pelo
 * endpoint `/macros/stats`. O painel que consome recebe os totais e o ranking
 * ja calculados e nao conhece o formato da API.
 */
export function useMacroStats() {
  const stats = ref([]);
  const period = ref(30);
  const loading = ref(false);
  const hasError = ref(false);

  // Mesmo padrao das fatias 5 e 6: trocar de periodo dispara requisicoes em
  // sequencia rapida, e a resposta de um periodo abandonado nao pode
  // sobrescrever a do periodo atual quando chega atrasada.
  let epoch = 0;

  const fetchStats = async () => {
    epoch += 1;
    const requestEpoch = epoch;
    loading.value = true;
    hasError.value = false;

    try {
      const { data } = await MacrosAPI.fetchStats({
        from: daysAgoIso(period.value),
      });
      if (requestEpoch !== epoch) return;
      stats.value = (data.payload || []).map(normalize);
    } catch (error) {
      if (requestEpoch !== epoch) return;
      stats.value = [];
      hasError.value = true;
    } finally {
      if (requestEpoch === epoch) loading.value = false;
    }
  };

  const totals = computed(() => {
    const sumOf = pick => stats.value.reduce((acc, row) => acc + pick(row), 0);

    const success = sumOf(row => row.counts.success);
    const partial = sumOf(row => row.counts.partial);
    const failed = sumOf(row => row.counts.failed);
    // Pendente fica fora da taxa, como no backend: a execucao ainda nao
    // terminou, e conta-la como fracasso derrubaria o numero durante um lote
    // grande so para ele voltar a subir quando o lote acabasse.
    const finished = success + partial + failed;

    return {
      executions: sumOf(row => row.total),
      failures: partial + failed,
      successRate:
        finished === 0 ? null : Math.round((success / finished) * 1000) / 10,
      activeMacros: stats.value.filter(row => row.total > 0).length,
    };
  });

  // Macro sem execucao no periodo fica de fora: um ranking preenchido com zeros
  // esconde as que de fato rodaram.
  const ranking = computed(() =>
    stats.value
      .filter(row => row.total > 0)
      .sort((a, b) => b.total - a.total)
      .slice(0, RANKING_SIZE)
  );

  const isEmpty = computed(() => totals.value.executions === 0);

  watch(period, fetchStats);

  return {
    stats,
    period,
    loading,
    hasError,
    totals,
    ranking,
    isEmpty,
    fetchStats,
  };
}
