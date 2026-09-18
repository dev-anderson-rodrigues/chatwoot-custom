import { computed, reactive, ref } from 'vue';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import operationReportsAPI, {
  emptyFilaHistorico,
} from 'dashboard/api/operationReports';
import { useReportPeriod, PERIOD_OPTIONS } from './useReportPeriod';

export { PERIOD_OPTIONS };

export const AGENT_TYPE_OPTIONS = ['all', 'human', 'bot'];

// Devolvido pelo `run` quando a requisicao foi cancelada por uma mais nova.
const SUPERSEDED = Symbol('superseded');

/**
 * [Onda 5 / fatia 4] Fila -- Historico.
 *
 * Mistura os dois padroes ja usados na onda: filtros completos (period/
 * customRange/teamId/agentType) do `useOrigemReport.js`, e KPIs current/
 * previous com `variationOf` do `useOwnershipReport.js` -- os dois builders
 * respondem perguntas diferentes (Origem nao compara periodo anterior, Robo
 * e humano nao tem filtro de equipe/agent_type), esta tela precisa dos dois.
 *
 * `report` traz as cinco secoes (kpis.current/previous, dailyEvolution,
 * byTeam, byAgent, capacityVsDemand); `variationOf` compara um campo de
 * `report.kpis.current` contra `report.kpis.previous`.
 */
export function useFilaHistoricoReport() {
  const report = ref(emptyFilaHistorico());
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
          operationReportsAPI.getFilaHistorico(
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

      report.value = result;
      loaded.value = true;
    } catch (error) {
      report.value = emptyFilaHistorico();
      hasError.value = true;
    }
  };

  /**
   * Variacao contra o periodo anterior, em pontos percentuais arredondados.
   * Devolve null quando nao havia base de comparacao: crescer "infinito%" a
   * partir de zero nao informa nada.
   */
  const variationOf = campo =>
    computed(() => {
      const antes = report.value.kpis.previous[campo];
      const agora = report.value.kpis.current[campo];
      if (!antes) return null;

      return Math.round(((agora - antes) / antes) * 100);
    });

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
    report,
    loading,
    // A tela usa isto para decidir entre spinner e numeros esmaecidos: depois
    // da primeira carga, trocar filtro mantem os numeros anteriores na tela.
    loaded,
    hasError,
    filters,
    range,
    variationOf,
    fetch,
    setPeriod,
    setCustomRange,
    setTeam,
    setAgentType,
  };
}
