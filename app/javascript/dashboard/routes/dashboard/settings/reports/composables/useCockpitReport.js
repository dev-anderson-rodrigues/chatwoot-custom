import { computed, reactive, ref } from 'vue';
import subDays from 'date-fns/subDays';
import startOfDay from 'date-fns/startOfDay';
import endOfDay from 'date-fns/endOfDay';
import getUnixTime from 'date-fns/getUnixTime';
import reportsAPI from 'dashboard/api/reports';

export const PERIOD_OPTIONS = ['7d', '30d', '90d'];

export const STATUS_OPTIONS = ['online', 'busy', 'offline'];

export const DATE_FIELDS = ['created', 'resolved'];

const SEARCH_DEBOUNCE = 400;

const DAYS_BY_PERIOD = { '7d': 6, '30d': 29, '90d': 89 };

const emptyTotals = () => ({
  agentsTotal: 0,
  agentsOnline: 0,
  agentsBusy: 0,
  agentsOffline: 0,
  conversationsTotal: 0,
  avgHandleSeconds: 0,
  avgCsat: 0,
});

const normalizeAgent = row => ({
  id: row.id,
  rank: row.rank,
  name: row.name,
  email: row.email,
  teamName: row.team_name,
  status: row.status,
  conversations: row.conversations ?? 0,
  resolutions: row.resolutions_count ?? 0,
  avgHandleSeconds: row.avg_handle_seconds ?? 0,
  avgFirstResponseSeconds: row.avg_first_response_seconds ?? 0,
  avgReplySeconds: row.avg_reply_seconds ?? 0,
  csat: row.csat,
  csatResponses: row.csat_responses ?? 0,
});

const normalizeTotals = kpis => ({
  agentsTotal: kpis?.agents_total ?? 0,
  agentsOnline: kpis?.agents_online ?? 0,
  agentsBusy: kpis?.agents_busy ?? 0,
  agentsOffline: kpis?.agents_offline ?? 0,
  conversationsTotal: kpis?.conversations_total ?? 0,
  avgHandleSeconds: kpis?.avg_handle_seconds ?? 0,
  avgCsat: kpis?.avg_csat ?? 0,
});

/**
 * [Onda 5] Estado, filtros e busca do Cockpit de Atendentes.
 *
 * A tela recebe os dados ja normalizados e nao conhece o formato da API, como
 * manda o frontend.mdc.
 */
export function useCockpitReport() {
  const agents = ref([]);
  const totals = ref(emptyTotals());
  const loading = ref(false);
  const hasError = ref(false);

  const filters = reactive({
    period: '30d',
    customRange: [],
    dateField: 'created',
    teamId: null,
    status: null,
    search: '',
  });

  // Sobe a cada requisicao: trocar filtro dispara chamadas em sequencia rapida,
  // e a resposta de um filtro abandonado nao pode sobrescrever a do atual.
  let epoch = 0;
  let searchTimer = null;

  const isCustomPeriod = computed(
    () => filters.period === 'custom' && filters.customRange.length === 2
  );

  const periodRange = computed(() => {
    const now = new Date();
    if (isCustomPeriod.value) {
      return {
        from: getUnixTime(startOfDay(filters.customRange[0])),
        to: getUnixTime(endOfDay(filters.customRange[1])),
      };
    }

    const days = DAYS_BY_PERIOD[filters.period] ?? DAYS_BY_PERIOD['30d'];

    return {
      from: getUnixTime(startOfDay(subDays(now, days))),
      to: getUnixTime(endOfDay(now)),
    };
  });

  const fetch = async () => {
    epoch += 1;
    const requestEpoch = epoch;
    loading.value = true;
    hasError.value = false;

    try {
      const { from, to } = periodRange.value;
      const { data } = await reportsAPI.getCockpitAtendentes({
        from,
        to,
        teamId: filters.teamId,
        status: filters.status,
        search: filters.search || undefined,
        dateField: filters.dateField,
      });
      if (requestEpoch !== epoch) return;
      agents.value = (data.agents || []).map(normalizeAgent);
      totals.value = normalizeTotals(data.kpis);
    } catch (error) {
      if (requestEpoch !== epoch) return;
      agents.value = [];
      totals.value = emptyTotals();
      hasError.value = true;
    } finally {
      if (requestEpoch === epoch) loading.value = false;
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
    periodRange,
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
