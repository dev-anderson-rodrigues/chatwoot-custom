import { computed, reactive, ref } from 'vue';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import operationReportsAPI, {
  emptyMotivos,
} from 'dashboard/api/operationReports';
import { useReportPeriod, PERIOD_OPTIONS } from './useReportPeriod';

export { PERIOD_OPTIONS };

export const AGENT_TYPE_OPTIONS = ['all', 'human', 'bot'];
export const DATE_FIELD_OPTIONS = ['created', 'resolved'];

// Devolvido pelo `run` quando a requisicao foi cancelada por uma mais nova.
const SUPERSEDED = Symbol('superseded');

/**
 * [Onda 5 / fatia 5] Motivos.
 *
 * Mesma base das fatias 3 e 4 (period/customRange/teamId/agentType do
 * `useOrigemReport`), mais os filtros de analise que so esta tela oferece:
 * caixa, atendente, status e o corte de data (abertura x encerramento).
 *
 * O que e proprio daqui: `labels` e uma escolha obrigatoria. Sem nenhuma
 * etiqueta selecionada a tela nao tem pergunta a fazer -- motivo e uma decisao
 * do usuario sobre quais etiquetas significam motivo de contato, e somar todas
 * produziria um "top motivos" que mistura prioridade, canal e campanha. O
 * `fetch` sai cedo nesse caso, e `needsSelection` diz a tela para mostrar o
 * estado de configuracao em vez de uma tabela zerada.
 */
export function useMotivosReport() {
  const report = ref(emptyMotivos());
  const hasError = ref(false);
  const loaded = ref(false);

  const filters = reactive({
    period: '30d',
    customRange: [],
    teamId: null,
    inboxId: null,
    dateField: 'created',
    labels: [],
    agentType: 'all',
  });

  const { range } = useReportPeriod(filters);
  const { run, isPending: loading } = useAbortableRequest();

  const hasSelection = computed(() => filters.labels.length > 0);

  // Estado de configuracao: o usuario ainda nao escolheu o que conta como
  // motivo. Diferente de "carregou e nao ha dado".
  const needsSelection = computed(() => !hasSelection.value);

  const fetch = async () => {
    hasError.value = false;

    if (!hasSelection.value) {
      report.value = emptyMotivos();
      loaded.value = false;
      return;
    }

    try {
      const result = await run(
        signal =>
          operationReportsAPI.getMotivos(
            {
              from: range.value.from,
              to: range.value.to,
              teamId: filters.teamId,
              inboxId: filters.inboxId,
              dateField: filters.dateField,
              labels: filters.labels,
              agentType: filters.agentType,
            },
            { signal }
          ),
        { onAbort: SUPERSEDED }
      );

      if (result === SUPERSEDED) return;

      report.value = result;
      loaded.value = true;
    } catch (error) {
      report.value = emptyMotivos();
      hasError.value = true;
    }
  };

  /**
   * Variacao do motivo contra o periodo anterior, em pontos percentuais
   * arredondados. Devolve null quando nao havia base de comparacao: um motivo
   * que apareceu agora nao "cresceu 100%", ele simplesmente nao existia antes,
   * e a tela mostra isso com outro rotulo.
   */
  const trendOf = row => {
    if (!row.previousTotal) return null;

    return Math.round(
      ((row.total - row.previousTotal) / row.previousTotal) * 100
    );
  };

  const applyFilter = (key, value) => {
    filters[key] = value;
    fetch();
  };

  const setPeriod = period => applyFilter('period', period);
  const setTeam = teamId => applyFilter('teamId', teamId);
  const setInbox = inboxId => applyFilter('inboxId', inboxId);
  const setDateField = dateField => applyFilter('dateField', dateField);
  const setLabels = labels => applyFilter('labels', labels);
  const setAgentType = agentType => applyFilter('agentType', agentType);

  const setCustomRange = customRange => {
    filters.customRange = customRange;
    filters.period = 'custom';
    fetch();
  };

  return {
    report,
    loading,
    // A tela usa isto para decidir entre spinner e numeros esmaecidos: depois
    // da primeira carga, trocar filtro mantem os numeros anteriores na tela.
    loaded,
    hasError,
    needsSelection,
    filters,
    range,
    trendOf,
    fetch,
    setPeriod,
    setCustomRange,
    setTeam,
    setInbox,
    setDateField,
    setLabels,
    setAgentType,
  };
}
