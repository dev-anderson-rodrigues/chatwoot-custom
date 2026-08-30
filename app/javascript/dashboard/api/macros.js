/* global axios */
import ApiClient from './ApiClient';

class MacrosAPI extends ApiClient {
  constructor() {
    super('macros', { accountScoped: true });
  }

  executeMacro({ macroId, conversationIds, inputs = {} }) {
    return axios.post(`${this.url}/${macroId}/execute`, {
      conversation_ids: conversationIds,
      inputs,
    });
  }

  // O backend limita o page size a 50; mandar mais nao quebra, so e ignorado.
  fetchExecutions(macroId, params = {}) {
    return axios.get(`${this.url}/${macroId}/executions`, {
      params: { limit: 20, offset: 0, ...params },
    });
  }

  fetchExecution(macroId, executionId) {
    return axios.get(`${this.url}/${macroId}/executions/${executionId}`);
  }

  // Janela padrao do backend e de 30 dias; `from`/`to` aceitam ISO 8601.
  fetchStats(params = {}) {
    return axios.get(`${this.url}/stats`, { params });
  }
}

export default new MacrosAPI();
