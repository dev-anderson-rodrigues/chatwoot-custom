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

export const emptyOrigem = () => ({
  summary: {
    total: 0,
    recebidos: 0,
    efetuados: 0,
    recebidosPct: 0,
    efetuadosPct: 0,
  },
  dailyEvolution: [],
  byOrigin: [],
  byTeam: [],
  byInbox: [],
  byAgent: [],
});

const normalizeOrigemSummary = summary => ({
  total: summary?.total ?? 0,
  recebidos: summary?.recebidos ?? 0,
  efetuados: summary?.efetuados ?? 0,
  recebidosPct: summary?.recebidos_pct ?? 0,
  efetuadosPct: summary?.efetuados_pct ?? 0,
});

const normalizeOrigemDay = row => ({
  date: row.date,
  recebidos: row.recebidos ?? 0,
  efetuados: row.efetuados ?? 0,
});

// `key`/`kind` sao as chaves estaveis que o builder manda (campaign/bot/
// template/agent_direct/other, automation/human) -- quem traduz para o
// usuario e a tela, nao o backend.
const normalizeOrigemOrigin = row => ({
  key: row.key,
  kind: row.kind,
  count: row.count ?? 0,
  pct: row.pct ?? 0,
});

// Usado por by_team/by_inbox/by_agent -- os tres tem o mesmo formato de linha.
// `name` nulo (sem equipe / sem atendente) chega assim de proposito; a tela
// decide o rotulo traduzido, como o `queueByTeam` da fatia 2 ja faz.
const normalizeOrigemBreakdownRow = row => ({
  id: row.id,
  name: row.name,
  total: row.total ?? 0,
  recebidos: row.recebidos ?? 0,
  efetuados: row.efetuados ?? 0,
});

const normalizeOrigem = data => ({
  summary: normalizeOrigemSummary(data?.summary),
  dailyEvolution: (data?.daily_evolution || []).map(normalizeOrigemDay),
  byOrigin: (data?.by_origin || []).map(normalizeOrigemOrigin),
  byTeam: (data?.by_team || []).map(normalizeOrigemBreakdownRow),
  byInbox: (data?.by_inbox || []).map(normalizeOrigemBreakdownRow),
  byAgent: (data?.by_agent || []).map(normalizeOrigemBreakdownRow),
});

export const emptyFilaHistoricoKpis = () => ({
  total: 0,
  avgWaitSeconds: 0,
  maxWaitSeconds: 0,
  abandonRate: 0,
  abandonedCount: 0,
});

export const emptyFilaHistorico = () => ({
  kpis: {
    current: emptyFilaHistoricoKpis(),
    previous: emptyFilaHistoricoKpis(),
  },
  dailyEvolution: [],
  byTeam: [],
  byAgent: [],
  capacityVsDemand: [],
});

const normalizeFilaHistoricoKpis = kpis => ({
  total: kpis?.total ?? 0,
  avgWaitSeconds: kpis?.avg_wait_seconds ?? 0,
  maxWaitSeconds: kpis?.max_wait_seconds ?? 0,
  abandonRate: kpis?.abandon_rate ?? 0,
  abandonedCount: kpis?.abandoned_count ?? 0,
});

const normalizeFilaHistoricoDay = row => ({
  date: row.date,
  volume: row.volume ?? 0,
  avgWaitMinutes: row.avg_wait_minutes ?? 0,
});

// `name` nulo (sem equipe / sem atendente) chega assim de proposito -- a tela
// decide o rotulo traduzido, mesmo padrao do `byTeam`/`byAgent` da fatia 3.
const normalizeFilaHistoricoTeamRow = row => ({
  id: row.id,
  name: row.name,
  total: row.total ?? 0,
  avgWaitSeconds: row.avg_wait_seconds ?? 0,
  maxWaitSeconds: row.max_wait_seconds ?? 0,
  abandoned: row.abandoned ?? 0,
});

const normalizeFilaHistoricoAgentRow = row => ({
  id: row.id,
  name: row.name,
  total: row.total ?? 0,
  avgWaitSeconds: row.avg_wait_seconds ?? 0,
  maxWaitSeconds: row.max_wait_seconds ?? 0,
  loadPct: row.load_pct ?? 0,
});

const normalizeFilaHistoricoCapacityRow = row => ({
  id: row.id,
  name: row.name,
  demand: row.demand ?? 0,
  agents: row.agents ?? 0,
  capacity: row.capacity ?? 0,
  usagePct: row.usage_pct ?? 0,
});

const normalizeFilaHistorico = data => ({
  kpis: {
    current: normalizeFilaHistoricoKpis(data?.kpis?.current),
    previous: normalizeFilaHistoricoKpis(data?.kpis?.previous),
  },
  dailyEvolution: (data?.daily_evolution || []).map(normalizeFilaHistoricoDay),
  byTeam: (data?.by_team || []).map(normalizeFilaHistoricoTeamRow),
  byAgent: (data?.by_agent || []).map(normalizeFilaHistoricoAgentRow),
  capacityVsDemand: (data?.capacity_vs_demand || []).map(
    normalizeFilaHistoricoCapacityRow
  ),
});

export const emptyMotivos = () => ({
  kpis: {
    reasonsCount: 0,
    conversationsTotal: 0,
    topReason: null,
    slowestReason: null,
    avgFcr: 0,
  },
  reasons: [],
  weeklyEvolution: { labels: [], series: [] },
});

// `topReason`/`slowestReason` ficam nulos quando nenhum motivo teve ocorrencia
// no periodo -- o backend nao elege um motivo zerado, e a tela esconde o
// cartao em vez de mostrar "motivo mais comum: — (0)".
const normalizeMotivosKpis = kpis => ({
  reasonsCount: kpis?.reasons_count ?? 0,
  conversationsTotal: kpis?.conversations_total ?? 0,
  topReason: kpis?.top_reason
    ? {
        name: kpis.top_reason.name,
        total: kpis.top_reason.total ?? 0,
        pct: kpis.top_reason.pct ?? 0,
      }
    : null,
  slowestReason: kpis?.slowest_reason
    ? {
        name: kpis.slowest_reason.name,
        avgHandleSeconds: kpis.slowest_reason.avg_handle_seconds ?? 0,
      }
    : null,
  avgFcr: kpis?.avg_fcr ?? 0,
});

// `color` nulo = etiqueta sem label correspondente na conta (foi apagado
// depois de usado); a tela aplica a cor neutra. `fcrPct` nulo = nao houve
// resolucao no periodo, que e diferente de FCR zero -- por isso nao vira 0.
// `previousTotal` vem cru: quem decide como mostrar "sem base de comparacao" e
// a tela, nao o backend.
const normalizeMotivosReason = row => ({
  name: row.name,
  color: row.color ?? null,
  total: row.total ?? 0,
  previousTotal: row.previous_total ?? 0,
  pct: row.pct ?? 0,
  avgHandleSeconds: row.avg_handle_seconds ?? 0,
  resolvedCount: row.resolved_count ?? 0,
  fcrCount: row.fcr_count ?? 0,
  fcrPct: row.fcr_pct ?? null,
  botResolvedPct: row.bot_resolved_pct ?? 0,
  botHandoffPct: row.bot_handoff_pct ?? 0,
});

const normalizeMotivos = data => ({
  kpis: normalizeMotivosKpis(data?.kpis),
  reasons: (data?.reasons || []).map(normalizeMotivosReason),
  weeklyEvolution: {
    labels: data?.weekly_evolution?.labels || [],
    series: (data?.weekly_evolution?.series || []).map(serie => ({
      name: serie.name,
      color: serie.color ?? null,
      data: serie.data || [],
    })),
  },
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

  /**
   * Recebidos e Efetuados: quanto o cliente abriu contra quanto a empresa
   * abriu, com evolucao diaria, origem do primeiro contato e quebra por
   * equipe/caixa/atendente.
   */
  async getOrigem({ from, to, teamId, agentType } = {}, { signal } = {}) {
    const { data } = await axios.get(`${this.url}/origem`, {
      params: {
        since: from,
        until: to,
        team_id: teamId,
        agent_type: agentType,
      },
      signal,
    });

    return normalizeOrigem(data);
  }

  /**
   * Fila -- Historico: tempo de espera, volume e abandono ao longo do tempo,
   * com KPIs comparados ao periodo anterior de mesma duracao.
   */
  async getFilaHistorico(
    { from, to, teamId, agentType } = {},
    { signal } = {}
  ) {
    const { data } = await axios.get(`${this.url}/fila_historico`, {
      params: {
        since: from,
        until: to,
        team_id: teamId,
        agent_type: agentType,
      },
      signal,
    });

    return normalizeFilaHistorico(data);
  }

  /**
   * Motivos: volume, tempo e resolucao por etiqueta de contato.
   *
   * `labels` e obrigatorio do ponto de vista do produto -- motivo e uma escolha
   * explicita, nao "toda etiqueta que existe". Sem selecao o backend devolve
   * estrutura vazia sem consultar o banco, e a tela nem chega a chamar aqui
   * (ver o guard em useMotivosReport).
   *
   * O endpoint tambem aceita `agent_id` e `status`, que a tela de hoje nao
   * oferece -- nao sao repassados aqui para nao virar parametro morto.
   */
  async getMotivos(
    { from, to, teamId, inboxId, dateField, labels, agentType } = {},
    { signal } = {}
  ) {
    const { data } = await axios.get(`${this.url}/motivos`, {
      params: {
        since: from,
        until: to,
        team_id: teamId,
        inbox_id: inboxId,
        date_field: dateField,
        labels,
        agent_type: agentType,
      },
      signal,
    });

    return normalizeMotivos(data);
  }
}

export default new OperationReportsAPI();
