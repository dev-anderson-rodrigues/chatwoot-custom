import { reactive, ref, onMounted } from 'vue';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import { useLiveRefresh } from 'dashboard/composables/useLiveRefresh';
import operationReportsAPI, {
  emptySupervisor,
} from 'dashboard/api/operationReports';

// Devolvido pelo `run` quando a requisicao foi cancelada por uma mais nova.
const SUPERSEDED = Symbol('superseded');

// Mesmo texto que REPORT.SUPERVISOR.AUTO_REFRESH promete na tela.
export const REFRESH_INTERVAL_MS = 30000;

export const AGENT_TYPE_OPTIONS = ['all', 'human', 'bot'];
export const STATUS_FILTER_OPTIONS = [
  'all',
  'na_fila',
  'atendendo',
  'aguardando',
];

/**
 * [Onda 5 / fatia 2] Monitoramento em tempo real (Supervisor).
 *
 * Sem periodo: e uma foto do agora, atualizada sozinha a cada
 * REFRESH_INTERVAL_MS via useLiveRefresh (o mesmo composable que os
 * relatorios ao vivo do upstream usam) -- ele encadeia o proximo `setTimeout`
 * so depois que o anterior termina, entao nunca empilha requisicao.
 */
export function useSupervisorReport() {
  const current = ref(emptySupervisor());
  const hasError = ref(false);
  const loaded = ref(false);

  const filters = reactive({
    teamId: null,
    agentType: 'all',
    statusFilter: 'all',
    page: 1,
  });

  const { run, isPending: loading } = useAbortableRequest();

  const fetch = async () => {
    try {
      const result = await run(
        signal => operationReportsAPI.getSupervisor(filters, { signal }),
        { onAbort: SUPERSEDED }
      );

      if (result === SUPERSEDED) return;

      current.value = result;
      loaded.value = true;
      hasError.value = false;
    } catch (error) {
      // A atualizacao automatica nao pode acender erro e apagar a tela que ja
      // estava de pe -- so a primeira carga tem essa permissao. Uma falha
      // isolada no meio do dia fica pelos numeros esmaecidos ate a proxima
      // tentativa se recuperar sozinha.
      if (!loaded.value) hasError.value = true;
    }
  };

  const { startRefetching } = useLiveRefresh(fetch, REFRESH_INTERVAL_MS);

  // Trocar qualquer filtro volta para a primeira pagina: manter a pagina 3 de
  // um recorte que agora tem duas mostraria uma tabela vazia por engano.
  const refetchFromStart = () => {
    filters.page = 1;
    fetch();
  };

  const setTeam = teamId => {
    filters.teamId = teamId;
    refetchFromStart();
  };

  const setAgentType = agentType => {
    filters.agentType = agentType;
    refetchFromStart();
  };

  const setStatusFilter = statusFilter => {
    filters.statusFilter = statusFilter;
    refetchFromStart();
  };

  const setPage = page => {
    filters.page = page;
    fetch();
  };

  onMounted(() => {
    fetch();
    startRefetching();
  });

  return {
    current,
    loading,
    // A tela usa isto para decidir entre spinner e numeros esmaecidos: depois
    // da primeira carga, atualizar (manual ou automatico) nunca apaga o que
    // ja esta na tela.
    loaded,
    hasError,
    filters,
    fetch,
    setTeam,
    setAgentType,
    setStatusFilter,
    setPage,
  };
}
