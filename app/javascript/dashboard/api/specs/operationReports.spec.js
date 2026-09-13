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

  describe('#getSupervisor', () => {
    const originalAxios = window.axios;
    const get = vi.fn();

    beforeEach(() => {
      window.axios = { get };
      get.mockResolvedValue({
        data: {
          kpis: {},
          queue_by_team: [],
          conversations: { items: [], counts: {}, pagination: {} },
          agents: [],
          alerts: [],
        },
      });
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    const call = (filters, options) =>
      operationReportsAPI.getSupervisor(filters, options);

    it('translates the filters into the names the api expects', async () => {
      await call({
        teamId: 7,
        agentType: 'bot',
        statusFilter: 'na_fila',
        page: 2,
        perPage: 50,
      });

      expect(get).toHaveBeenCalledWith(
        expect.stringContaining('/reports/supervisor'),
        expect.objectContaining({
          params: {
            team_id: 7,
            agent_type: 'bot',
            status_filter: 'na_fila',
            page: 2,
            per_page: 50,
          },
        })
      );
    });

    it('passes the abort signal through, so a stale request can be cancelled', async () => {
      const { signal } = new AbortController();

      await call({}, { signal });

      expect(get.mock.calls[0][1].signal).toBe(signal);
    });

    it('hands the screen domain names for every section', async () => {
      get.mockResolvedValue({
        data: {
          kpis: {
            in_progress: 5,
            in_queue: 2,
            in_queue_unfiltered: 3,
            longest_wait_minutes: 45,
            longest_wait_window_days: 30,
            stale_in_queue: 1,
            agents_online: 2,
            agents_total: 3,
            avg_load: 2.5,
          },
          queue_by_team: [
            {
              id: 4,
              name: 'Suporte',
              in_queue: 2,
              in_progress: 5,
              agents_online: 2,
            },
          ],
          conversations: {
            items: [
              {
                id: 101,
                contact_name: 'Maria Lima',
                contact_phone: '+55 11 99999-0000',
                agent_name: 'Ana Souza',
                inbox_name: 'WhatsApp',
                channel_type: 'Channel::Whatsapp',
                labels: ['vip'],
                priority: 'high',
                duration_minutes: 12,
                last_message_minutes: 3,
                status: 'atendendo',
              },
            ],
            counts: { all: 7, na_fila: 2, atendendo: 4, aguardando: 1 },
            pagination: {
              page: 1,
              per_page: 25,
              total_count: 7,
              total_pages: 1,
            },
          },
          agents: [{ id: 1, name: 'Ana Souza', status: 'online', load: 3 }],
          alerts: [
            {
              id: 202,
              contact_name: 'Espera Longa',
              minutes: 22,
              inbox_name: 'Email',
              labels: [],
            },
          ],
        },
      });

      const result = await call({});

      expect(result.kpis).toEqual({
        inProgress: 5,
        inQueue: 2,
        inQueueUnfiltered: 3,
        longestWaitMinutes: 45,
        longestWaitWindowDays: 30,
        staleInQueue: 1,
        agentsOnline: 2,
        agentsTotal: 3,
        avgLoad: 2.5,
      });
      expect(result.queueByTeam).toEqual([
        { id: 4, name: 'Suporte', inQueue: 2, inProgress: 5, agentsOnline: 2 },
      ]);
      expect(result.conversations.items[0]).toEqual({
        id: 101,
        contactName: 'Maria Lima',
        contactPhone: '+55 11 99999-0000',
        agentName: 'Ana Souza',
        inboxName: 'WhatsApp',
        channelType: 'Channel::Whatsapp',
        labels: ['vip'],
        priority: 'high',
        durationMinutes: 12,
        lastMessageMinutes: 3,
        status: 'atendendo',
      });
      expect(result.conversations.counts).toEqual({
        all: 7,
        naFila: 2,
        atendendo: 4,
        aguardando: 1,
      });
      expect(result.conversations.pagination).toEqual({
        page: 1,
        perPage: 25,
        totalCount: 7,
        totalPages: 1,
      });
      expect(result.agents).toEqual([
        { id: 1, name: 'Ana Souza', status: 'online', load: 3 },
      ]);
      expect(result.alerts).toEqual([
        {
          id: 202,
          contactName: 'Espera Longa',
          minutes: 22,
          inboxName: 'Email',
          labels: [],
        },
      ]);
    });

    it('survives an empty response instead of crashing the screen', async () => {
      get.mockResolvedValue({ data: {} });

      const result = await call({});

      expect(result.kpis.inProgress).toBe(0);
      expect(result.queueByTeam).toEqual([]);
      expect(result.conversations.items).toEqual([]);
      expect(result.conversations.pagination.page).toBe(1);
      expect(result.agents).toEqual([]);
      expect(result.alerts).toEqual([]);
    });
  });

  describe('#getOrigem', () => {
    const originalAxios = window.axios;
    const get = vi.fn();

    beforeEach(() => {
      window.axios = { get };
      get.mockResolvedValue({
        data: {
          summary: {},
          daily_evolution: [],
          by_origin: [],
          by_team: [],
          by_inbox: [],
          by_agent: [],
        },
      });
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    const call = (filters, options) =>
      operationReportsAPI.getOrigem(filters, options);

    it('translates the filters into the names the api expects', async () => {
      await call({ from: 1000, to: 2000, teamId: 7, agentType: 'bot' });

      expect(get).toHaveBeenCalledWith(
        expect.stringContaining('/reports/origem'),
        expect.objectContaining({
          params: { since: 1000, until: 2000, team_id: 7, agent_type: 'bot' },
        })
      );
    });

    it('passes the abort signal through, so a stale request can be cancelled', async () => {
      const { signal } = new AbortController();

      await call({ from: 1, to: 2 }, { signal });

      expect(get.mock.calls[0][1].signal).toBe(signal);
    });

    it('hands the screen domain names for every section', async () => {
      get.mockResolvedValue({
        data: {
          summary: {
            total: 10,
            recebidos: 6,
            efetuados: 4,
            recebidos_pct: 60.0,
            efetuados_pct: 40.0,
          },
          daily_evolution: [
            { date: '2026-01-01', recebidos: 3, efetuados: 1 },
          ],
          by_origin: [
            { key: 'campaign', kind: 'automation', count: 2, pct: 50.0 },
          ],
          by_team: [
            { id: 4, name: 'Suporte', total: 5, recebidos: 3, efetuados: 2 },
          ],
          by_inbox: [
            { id: 9, name: 'WhatsApp', total: 5, recebidos: 3, efetuados: 2 },
          ],
          by_agent: [
            { id: 1, name: 'Ana Souza', total: 5, recebidos: 3, efetuados: 2 },
          ],
        },
      });

      const result = await call({ from: 1, to: 2 });

      expect(result.summary).toEqual({
        total: 10,
        recebidos: 6,
        efetuados: 4,
        recebidosPct: 60.0,
        efetuadosPct: 40.0,
      });
      expect(result.dailyEvolution).toEqual([
        { date: '2026-01-01', recebidos: 3, efetuados: 1 },
      ]);
      expect(result.byOrigin).toEqual([
        { key: 'campaign', kind: 'automation', count: 2, pct: 50.0 },
      ]);
      expect(result.byTeam).toEqual([
        { id: 4, name: 'Suporte', total: 5, recebidos: 3, efetuados: 2 },
      ]);
      expect(result.byInbox).toEqual([
        { id: 9, name: 'WhatsApp', total: 5, recebidos: 3, efetuados: 2 },
      ]);
      expect(result.byAgent).toEqual([
        { id: 1, name: 'Ana Souza', total: 5, recebidos: 3, efetuados: 2 },
      ]);
    });

    it('keeps a null name (no team / no agent) instead of inventing a label', async () => {
      get.mockResolvedValue({
        data: {
          summary: {},
          daily_evolution: [],
          by_origin: [],
          by_team: [{ id: null, name: null, total: 2, recebidos: 1, efetuados: 1 }],
          by_inbox: [],
          by_agent: [],
        },
      });

      const result = await call({ from: 1, to: 2 });

      expect(result.byTeam[0].name).toBeNull();
    });

    it('survives an empty response instead of crashing the screen', async () => {
      get.mockResolvedValue({ data: {} });

      const result = await call({ from: 1, to: 2 });

      expect(result.summary).toEqual({
        total: 0,
        recebidos: 0,
        efetuados: 0,
        recebidosPct: 0,
        efetuadosPct: 0,
      });
      expect(result.dailyEvolution).toEqual([]);
      expect(result.byOrigin).toEqual([]);
      expect(result.byTeam).toEqual([]);
      expect(result.byInbox).toEqual([]);
      expect(result.byAgent).toEqual([]);
    });
  });
});
