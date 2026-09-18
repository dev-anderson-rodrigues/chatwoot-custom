import { reactive, ref } from 'vue';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import operationReportsAPI, {
  emptyOrigem,
} from 'dashboard/api/operationReports';
import { useReportPeriod, PERIOD_OPTIONS } from './useReportPeriod';

export { PERIOD_OPTIONS };

export const AGENT_TYPE_OPTIONS = ['all', 'human', 'bot'];

// Devolvido pelo `run` quando a requisicao foi cancelada por uma mais nova.
const SUPERSEDED = Symbol('superseded');

/**
 * [Onda 5 / fatia 3] Recebidos e Efetuados.
 *
 * Primeiro consumidor de verdade do intervalo livre do `useReportPeriod`
 * (`customRange`) -- as fatias anteriores so ofereciam os atalhos de 7/30/90
 * dias.
 */
export function useOrigemReport() {
  const current = ref(emptyOrigem());
  const hasError = ref(false);
  const loaded = ref(false);

  const filters = reactive({
    period: '30d',
    customRange: [],
    teamId: null,
    agentType: 'all',
  });

  const { range } = useReportPeriod(filters);
  const { run, isPending: loading } = useAbortableRequest();

  const fetch = async () => {
    hasError.value = false;

    try {
      const result = await run(
        signal =>
          operationReportsAPI.getOrigem(
            {
              from: range.value.from,
              to: range.value.to,
              teamId: filters.teamId,
              agentType: filters.agentType,
            },
            { signal }
          ),
        { onAbort: SUPERSEDED }
      );

      if (result === SUPERSEDED) return;

      current.value = result;
      loaded.value = true;
    } catch (error) {
      current.value = emptyOrigem();
      hasError.value = true;
    }
  };

  const setPeriod = period => {
    filters.period = period;
    fetch();
  };

  const setCustomRange = customRange => {
    filters.customRange = customRange;
    filters.period = 'custom';
    fetch();
  };

  const setTeam = teamId => {
    filters.teamId = teamId;
    fetch();
  };

  const setAgentType = agentType => {
    filters.agentType = agentType;
    fetch();
  };

  return {
    current,
    loading,
    // A tela usa isto para decidir entre spinner e numeros esmaecidos: depois
    // da primeira carga, trocar filtro mantem os numeros anteriores na tela.
    loaded,
    hasError,
    filters,
    range,
    fetch,
    setPeriod,
    setCustomRange,
    setTeam,
    setAgentType,
  };
}
