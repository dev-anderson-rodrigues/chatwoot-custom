import operationReportsAPI from '../operationReports';
import ApiClient from '../ApiClient';

describe('#OperationReports API', () => {
  it('creates correct instance', () => {
    expect(operationReportsAPI).toBeInstanceOf(ApiClient);
    expect(operationReportsAPI.apiVersion).toBe('/api/v2');
    expect(operationReportsAPI).toHaveProperty('getCockpitAtendentes');
  });

  describe('#getCockpitAtendentes', () => {
    const originalAxios = window.axios;
    const get = vi.fn();

    beforeEach(() => {
      window.axios = { get };
      get.mockResolvedValue({ data: { agents: [], kpis: {} } });
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    const call = (filters, options) =>
      operationReportsAPI.getCockpitAtendentes(filters, options);

    it('translates the filters into the names the api expects', async () => {
      await call({
        from: 1000,
        to: 2000,
        teamId: 7,
        status: 'busy',
        search: 'ana',
        dateField: 'resolved',
      });

      expect(get).toHaveBeenCalledWith(
        expect.stringContaining('/reports/cockpit_atendentes'),
        expect.objectContaining({
          params: {
            since: 1000,
            until: 2000,
            team_id: 7,
            status: 'busy',
            search: 'ana',
            date_field: 'resolved',
          },
        })
      );
    });

    it('passes the abort signal through, so a stale request can be cancelled', async () => {
      const { signal } = new AbortController();

      await call({ from: 1, to: 2 }, { signal });

      expect(get.mock.calls[0][1].signal).toBe(signal);
    });

    it('hands the screen domain names instead of the api payload', async () => {
      get.mockResolvedValue({
        data: {
          agents: [
            {
              id: 1,
              rank: 2,
              name: 'Ana',
              email: 'ana@exemplo.com',
              team_name: 'Suporte',
              status: 'online',
              conversations: 12,
              resolutions_count: 9,
              avg_handle_seconds: 3600,
              avg_first_response_seconds: 120,
              avg_reply_seconds: 60,
              csat: 4.5,
              csat_responses: 2,
            },
          ],
          kpis: { agents_total: 1, conversations_total: 12, avg_csat: 4.5 },
        },
      });

      const { agents, totals } = await call({ from: 1, to: 2 });

      expect(agents[0]).toEqual({
        id: 1,
        rank: 2,
        name: 'Ana',
        email: 'ana@exemplo.com',
        teamName: 'Suporte',
        status: 'online',
        conversations: 12,
        resolutions: 9,
        avgHandleSeconds: 3600,
        avgFirstResponseSeconds: 120,
        avgReplySeconds: 60,
        csat: 4.5,
        csatResponses: 2,
      });
      expect(totals.agentsTotal).toBe(1);
      expect(totals.conversationsTotal).toBe(12);
    });

    it('fills missing numbers with zero, but keeps csat null', async () => {
      // Zero em csat seria uma nota; "sem nota" e outra coisa, e a tela mostra
      // um texto proprio para isso.
      get.mockResolvedValue({ data: { agents: [{ id: 1 }], kpis: null } });

      const { agents, totals } = await call({ from: 1, to: 2 });

      expect(agents[0].conversations).toBe(0);
      expect(agents[0].resolutions).toBe(0);
      expect(agents[0].csat).toBeNull();
      expect(totals.agentsTotal).toBe(0);
      expect(totals.avgCsat).toBe(0);
    });

    it('survives a response without agents', async () => {
      get.mockResolvedValue({ data: {} });

      const { agents, totals } = await call({ from: 1, to: 2 });

      expect(agents).toEqual([]);
      expect(totals.conversationsTotal).toBe(0);
    });
  });

  describe('#getOwnershipSummary', () => {
    const originalAxios = window.axios;
    const get = vi.fn();

    beforeEach(() => {
      window.axios = { get };
      get.mockResolvedValue({ data: { current: {}, previous: {} } });
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('asks for the window with the names the api expects', async () => {
      await operationReportsAPI.getOwnershipSummary({ from: 1000, to: 2000 });

      expect(get).toHaveBeenCalledWith(
        expect.stringContaining('/reports/ownership_summary'),
        expect.objectContaining({ params: { since: 1000, until: 2000 } })
      );
    });

    it('hands the screen domain names for both windows', async () => {
      get.mockResolvedValue({
        data: {
          current: {
            bot_resolutions: 8,
            human_resolutions: 2,
            bot_avg_resolution_seconds: 120,
            human_avg_resolution_seconds: 900,
            human_avg_first_response_seconds: 60,
            handoffs: 3,
          },
          previous: { bot_resolutions: 4 },
        },
      });

      const { current, previous } =
        await operationReportsAPI.getOwnershipSummary({
          from: 1,
          to: 2,
        });

      expect(current.botResolutions).toBe(8);
      expect(current.humanResolutions).toBe(2);
      expect(current.botAvgResolutionSeconds).toBe(120);
      expect(current.handoffs).toBe(3);
      expect(previous.botResolutions).toBe(4);
      // O que o backend nao mandou vira zero, nao undefined: a tela soma esses
      // numeros.
      expect(previous.humanResolutions).toBe(0);
    });
  });
});
