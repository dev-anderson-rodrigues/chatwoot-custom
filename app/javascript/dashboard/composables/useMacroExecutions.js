import { computed, reactive, ref, watch } from 'vue';
import MacrosAPI from 'dashboard/api/macros';

export const PAGE_SIZE = 20;

export const EXECUTION_STATUSES = ['pending', 'success', 'partial', 'failed'];

const emptyFilters = () => ({ status: '', userId: '', from: '', to: '' });

const normalize = execution => ({
  id: execution.id,
  createdAt: execution.created_at,
  agentName: execution.user?.available_name || execution.user?.name || '',
  conversationDisplayId: execution.conversation_display_id || null,
  status: execution.status,
  actionsRun: execution.actions_run ?? 0,
  actionsTotal: execution.actions_total ?? 0,
  inputs: execution.inputs || {},
  errorMessage: execution.error_message || '',
});

// O backend compara `created_at <= to`, e uma data crua vira meia-noite: sem
// isto, filtrar "ate 05/09" esconde tudo o que rodou no proprio dia 05.
const endOfDay = date => (date ? `${date}T23:59:59` : undefined);

const toParams = (filters, page) => ({
  status: filters.status || undefined,
  user_id: filters.userId || undefined,
  from: filters.from || undefined,
  to: endOfDay(filters.to),
  limit: PAGE_SIZE,
  offset: (page - 1) * PAGE_SIZE,
});

/**
 * [Fatia 6] Historico de execucoes de uma macro: lista paginada com filtros de
 * status, agente e periodo, servida pelo endpoint `/macros/:id/executions`.
 *
 * O componente que consome recebe os registros ja normalizados e nao conhece o
 * formato da API.
 */
export function useMacroExecutions(macroId) {
  const executions = ref([]);
  const total = ref(0);
  const page = ref(1);
  const loading = ref(false);
  const hasError = ref(false);
  const filters = reactive(emptyFilters());

  // Sobe a cada requisicao. Trocar filtro e pagina dispara requisicoes em
  // sequencia rapida, e a resposta de uma consulta abandonada nao pode
  // sobrescrever a da consulta atual quando chega atrasada.
  let epoch = 0;

  const hasActiveFilters = computed(() =>
    Object.values(filters).some(value => value !== '')
  );

  const fetch = async () => {
    epoch += 1;
    const requestEpoch = epoch;
    loading.value = true;
    hasError.value = false;

    try {
      const { data } = await MacrosAPI.fetchExecutions(
        macroId,
        toParams(filters, page.value)
      );
      if (requestEpoch !== epoch) return;
      executions.value = (data.payload || []).map(normalize);
      total.value = data.meta?.total ?? executions.value.length;
    } catch (error) {
      if (requestEpoch !== epoch) return;
      executions.value = [];
      total.value = 0;
      hasError.value = true;
    } finally {
      if (requestEpoch === epoch) loading.value = false;
    }
  };

  const clearFilters = () => Object.assign(filters, emptyFilters());

  // Filtrar recomeca da primeira pagina: manter a pagina 4 depois de estreitar
  // o resultado para dez registros mostraria uma lista vazia.
  watch(filters, () => {
    if (page.value === 1) fetch();
    else page.value = 1;
  });

  watch(page, fetch);

  return {
    executions,
    total,
    page,
    loading,
    hasError,
    filters,
    hasActiveFilters,
    clearFilters,
    fetch,
  };
}
