import axios from 'axios';
import macros from '../macros';
import ApiClient from '../ApiClient';

// Mesmo padrao dos demais specs de api/: o ApiClient usa o axios global.
global.axios = axios;
vi.mock('axios');

describe('#macrosAPI', () => {
  it('creates correct instance', () => {
    expect(macros).toBeInstanceOf(ApiClient);
    expect(macros).toHaveProperty('get');
    expect(macros).toHaveProperty('create');
    expect(macros).toHaveProperty('update');
    expect(macros).toHaveProperty('delete');
    expect(macros).toHaveProperty('show');
    expect(macros).toHaveProperty('executeMacro');
    expect(macros).toHaveProperty('fetchExecutions');
    expect(macros).toHaveProperty('fetchExecution');
    expect(macros).toHaveProperty('fetchStats');
    expect(macros.url).toBe('/api/v1/macros');
  });

  describe('API calls', () => {
    beforeEach(() => {
      vi.clearAllMocks();
    });

    it('#executeMacro sends the filled inputs along with the conversations', () => {
      macros.executeMacro({
        macroId: 1,
        conversationIds: [10, 11],
        inputs: { cpf: '123' },
      });

      expect(axios.post).toHaveBeenCalledWith('/api/v1/macros/1/execute', {
        conversation_ids: [10, 11],
        inputs: { cpf: '123' },
      });
    });

    it('#executeMacro defaults inputs to an empty object', () => {
      macros.executeMacro({ macroId: 1, conversationIds: [10] });

      expect(axios.post).toHaveBeenCalledWith('/api/v1/macros/1/execute', {
        conversation_ids: [10],
        inputs: {},
      });
    });

    it('#fetchExecutions applies default pagination', () => {
      macros.fetchExecutions(7);

      expect(axios.get).toHaveBeenCalledWith('/api/v1/macros/7/executions', {
        params: { limit: 20, offset: 0 },
      });
    });

    it('#fetchExecutions lets the caller override pagination and filter', () => {
      macros.fetchExecutions(7, { limit: 50, offset: 100, status: 'failed' });

      expect(axios.get).toHaveBeenCalledWith('/api/v1/macros/7/executions', {
        params: { limit: 50, offset: 100, status: 'failed' },
      });
    });

    it('#fetchExecution requests a single execution', () => {
      macros.fetchExecution(7, 42);

      expect(axios.get).toHaveBeenCalledWith('/api/v1/macros/7/executions/42');
    });

    it('#fetchStats forwards the date range', () => {
      macros.fetchStats({ from: '2026-08-01', to: '2026-08-30' });

      expect(axios.get).toHaveBeenCalledWith('/api/v1/macros/stats', {
        params: { from: '2026-08-01', to: '2026-08-30' },
      });
    });
  });
});
