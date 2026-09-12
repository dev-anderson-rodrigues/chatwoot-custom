/* global axios */
import ApiClient from './ApiClient';

/**
 * [Onda 5] Relatorios de operacao do fork.
 *
 * Arquivo proprio em vez de crescer o `reports.js` do upstream: as acoes moram
 * no OperationReportsController pelo mesmo motivo, e arquivo novo nao conflita
 * em sync nenhum.
 *
 * Aqui mora o contrato com a API -- os nomes que o backend espera e a traducao
 * da resposta para o dominio do front. A tela e o composable nunca veem
 * snake_case, como manda o frontend.mdc.
 */

export const emptyTotals = () => ({
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
  // `csat` fica nulo de proposito: zero seria uma nota, e "sem nota" e outra
  // coisa.
  csat: row.csat ?? null,
  csatResponses: row.csat_responses ?? 0,
});

export const emptyOwnership = () => ({
  botResolutions: 0,
  humanResolutions: 0,
  botAvgResolutionSeconds: 0,
  humanAvgResolutionSeconds: 0,
  humanAvgFirstResponseSeconds: 0,
  handoffs: 0,
});

const normalizeOwnership = summary => ({
  botResolutions: summary?.bot_resolutions ?? 0,
  humanResolutions: summary?.human_resolutions ?? 0,
  botAvgResolutionSeconds: summary?.bot_avg_resolution_seconds ?? 0,
  humanAvgResolutionSeconds: summary?.human_avg_resolution_seconds ?? 0,
  humanAvgFirstResponseSeconds: summary?.human_avg_first_response_seconds ?? 0,
  handoffs: summary?.handoffs ?? 0,
});

export const emptySupervisor = () => ({
  kpis: {
    inProgress: 0,
    inQueue: 0,
    inQueueUnfiltered: 0,
    longestWaitMinutes: 0,
    longestWaitWindowDays: 0,
    staleInQueue: 0,
    agentsOnline: 0,
    agentsTotal: 0,
    avgLoad: 0,
  },
  queueByTeam: [],
  conversations: {
    items: [],
    counts: { all: 0, naFila: 0, atendendo: 0, aguardando: 0 },
    pagination: { page: 1, perPage: 25, totalCount: 0, totalPages: 0 },
  },
  agents: [],
  alerts: [],
});

const normalizeSupervisorKpis = kpis => ({
  inProgress: kpis?.in_progress ?? 0,
  inQueue: kpis?.in_queue ?? 0,
  inQueueUnfiltered: kpis?.in_queue_unfiltered ?? 0,
  longestWaitMinutes: kpis?.longest_wait_minutes ?? 0,
  longestWaitWindowDays: kpis?.longest_wait_window_days ?? 0,
  staleInQueue: kpis?.stale_in_queue ?? 0,
  agentsOnline: kpis?.agents_online ?? 0,
  agentsTotal: kpis?.agents_total ?? 0,
  avgLoad: kpis?.avg_load ?? 0,
});

const normalizeQueueByTeam = rows =>
  (rows || []).map(row => ({
    id: row.id,
    // Time nulo e a linha "Sem equipe" que o builder so inclui quando ha
    // conversa nela -- a tela decide como rotular.
    name: row.name,
    inQueue: row.in_queue ?? 0,
    inProgress: row.in_progress ?? 0,
    agentsOnline: row.agents_online ?? 0,
  }));

const normalizeSupervisorConversation = item => ({
  id: item.id,
  // Sem fallback aqui: contato vazio vira "—" na celula, no mesmo padrao do
  // CsatContactCell.
  contactName: item.contact_name,
  contactPhone: item.contact_phone,
  agentName: item.agent_name,
  inboxName: item.inbox_name,
  channelType: item.channel_type,
  labels: item.labels ?? [],
  priority: item.priority,
  durationMinutes: item.duration_minutes ?? 0,
  lastMessageMinutes: item.last_message_minutes ?? 0,
  status: item.status,
});

const normalizeSupervisorCounts = counts => ({
  all: counts?.all ?? 0,
  naFila: counts?.na_fila ?? 0,
  atendendo: counts?.atendendo ?? 0,
  aguardando: counts?.aguardando ?? 0,
});

const normalizeSupervisorPagination = pagination => ({
  page: pagination?.page ?? 1,
  perPage: pagination?.per_page ?? 25,
  totalCount: pagination?.total_count ?? 0,
  totalPages: pagination?.total_pages ?? 0,
});

const normalizeSupervisorAgent = agent => ({
  id: agent.id,
  name: agent.name,
  status: agent.status,
  load: agent.load ?? 0,
});

const normalizeSupervisorAlert = alert => ({
  id: alert.id,
  contactName: alert.contact_name,
  minutes: alert.minutes ?? 0,
  inboxName: alert.inbox_name,
  labels: alert.labels ?? [],
});

const normalizeSupervisor = data => ({
  kpis: normalizeSupervisorKpis(data?.kpis),
  queueByTeam: normalizeQueueByTeam(data?.queue_by_team),
  conversations: {
    items: (data?.conversations?.items || []).map(
      normalizeSupervisorConversation
    ),
    counts: normalizeSupervisorCounts(data?.conversations?.counts),
    pagination: normalizeSupervisorPagination(data?.conversations?.pagination),
  },
  agents: (data?.agents || []).map(normalizeSupervisorAgent),
  alerts: (data?.alerts || []).map(normalizeSupervisorAlert),
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

class OperationReportsAPI extends ApiClient {
  constructor() {
    super('reports', { accountScoped: true, apiVersion: 'v2' });
  }

  /**
   * Cockpit de atendentes. `dateField` escolhe entre contar conversas por
   * abertura ou por encerramento -- sao perguntas diferentes para a operacao.
   *
   * `signal` vem do useAbortableRequest: trocar de filtro cancela a requisicao
   * anterior em vez de deixar duas respostas correndo.
   */
  async getCockpitAtendentes(
    { from, to, teamId, status, search, dateField } = {},
    { signal } = {}
  ) {
    const { data } = await axios.get(`${this.url}/cockpit_atendentes`, {
      params: {
        since: from,
        until: to,
        team_id: teamId,
        status,
        search,
        date_field: dateField,
      },
      signal,
    });

    return {
      agents: (data?.agents || []).map(normalizeAgent),
      totals: normalizeTotals(data?.kpis),
    };
  }

  /**
   * Resumo de atendimento separado por robo e humano, no periodo e no periodo
   * anterior de mesmo tamanho -- e a comparacao que da sentido a variacao.
   */
  async getOwnershipSummary({ from, to } = {}, { signal } = {}) {
    const { data } = await axios.get(`${this.url}/ownership_summary`, {
      params: { since: from, until: to },
      signal,
    });

    return {
      current: normalizeOwnership(data?.current),
      previous: normalizeOwnership(data?.previous),
    };
  }

  /**
   * Monitoramento em tempo real (Supervisor). A tela se atualiza sozinha (ver
   * useLiveRefresh no composable), por isso cancelamos via signal a
   * requisicao anterior -- nao tem periodo de data, so foto atual.
   */
  async getSupervisor(
    { teamId, agentType, statusFilter, page, perPage } = {},
    { signal } = {}
  ) {
    const { data } = await axios.get(`${this.url}/supervisor`, {
      params: {
        team_id: teamId,
        agent_type: agentType,
        status_filter: statusFilter,
        page,
        per_page: perPage,
      },
      signal,
    });

    return normalizeSupervisor(data);
  }
}

export default new OperationReportsAPI();
