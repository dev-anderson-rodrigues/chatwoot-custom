import { computed, reactive, ref } from 'vue';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import operationReportsAPI, {
  emptyTotals,
} from 'dashboard/api/operationReports';
import { useReportPeriod, PERIOD_OPTIONS } from './useReportPeriod';

export { PERIOD_OPTIONS };

export const STATUS_OPTIONS = ['online', 'busy', 'offline'];

export const DATE_FIELDS = ['created', 'resolved'];

const SEARCH_DEBOUNCE = 400;

// Devolvido pelo `run` quando a requisicao foi cancelada por uma mais nova:
// quem cancelou e quem manda no estado agora.
const SUPERSEDED = Symbol('superseded');

/**
 * [Onda 5] Estado, filtros e busca do Cockpit de Atendentes.
 *
 * A tela recebe os dados ja normalizados pelo service e nao conhece o formato
 * da API, como manda o frontend.mdc.
 */
export function useCockpitReport() {
  const agents = ref([]);
  const totals = ref(emptyTotals());
  const hasError = ref(false);

  const filters = reactive({
    period: '30d',
    customRange: [],
    dateField: 'created',
    teamId: null,
    status: null,
    search: '',
  });

  const { range } = useReportPeriod(filters);

  // Trocar filtro dispara chamadas em sequencia rapida. O `run` cancela a
  // anterior pelo AbortSignal, entao a resposta de um filtro abandonado nunca
  // sobrescreve a do atual -- e `isPending` ja e o estado de carregando.
  const { run, isPending: loading } = useAbortableRequest();

  let searchTimer = null;

  const fetch = async () => {
    hasError.value = false;

    try {
      const result = await run(
        signal =>
          operationReportsAPI.getCockpitAtendentes(
            {
              ...range.value,
              teamId: filters.teamId,
              status: filters.status,
              search: filters.search || undefined,
              dateField: filters.dateField,
            },
            { signal }
          ),
        { onAbort: SUPERSEDED }
      );

      if (result === SUPERSEDED) return;

      agents.value = result.agents;
      totals.value = result.totals;
    } catch (error) {
      agents.value = [];
      totals.value = emptyTotals();
      hasError.value = true;
    }
  };

  const setPeriod = period => {
    filters.period = period;
    fetch();
  };

  const setCustomRange = ([start, end]) => {
    if (!start || !end) return;

    filters.customRange = [start, end];
    filters.period = 'custom';
    fetch();
  };

  const setDateField = dateField => {
    filters.dateField = dateField;
    fetch();
  };

  const setTeam = teamId => {
    filters.teamId = teamId;
    fetch();
  };

  const setStatus = status => {
    filters.status = status;
    fetch();
  };

  // A busca so dispara quando o agente para de digitar; sem isso cada tecla
  // vira uma requisicao.
  const setSearch = term => {
    filters.search = term;
    clearTimeout(searchTimer);
    searchTimer = setTimeout(fetch, SEARCH_DEBOUNCE);
  };

  const clearSearch = () => {
    clearTimeout(searchTimer);
    filters.search = '';
    fetch();
  };

  const isEmpty = computed(() => agents.value.length === 0);

  return {
    agents,
    totals,
    loading,
    hasError,
    filters,
    isEmpty,
    range,
    fetch,
    setPeriod,
    setCustomRange,
    setDateField,
    setTeam,
    setStatus,
    setSearch,
    clearSearch,
  };
}
