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
}

export default new OperationReportsAPI();
