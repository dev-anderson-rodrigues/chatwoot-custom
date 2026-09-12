import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { withFullI18n } from 'test-i18n';
import MonitoramentoSupervisor from '../MonitoramentoSupervisor.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';

withFullI18n();

const getSupervisor = vi.fn();
const teams = ref([{ id: 4, name: 'Suporte' }]);

vi.mock('dashboard/api/operationReports', () => ({
  default: {
    getSupervisor: (...args) => getSupervisor(...args),
  },
  emptySupervisor: () => ({
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
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => teams,
}));

// A tela se atualiza sozinha via useLiveRefresh; o intervalo em si nao e desta
// fatia (nenhum composable do fork tem spec direto para ele). Aqui interessa
// so o `fetch` que ele chamaria, exercitado diretamente pelas trocas de
// filtro abaixo.
vi.mock('dashboard/composables/useLiveRefresh', () => ({
  useLiveRefresh: () => ({ startRefetching: vi.fn(), stopRefetching: vi.fn() }),
}));

const payload = (overrides = {}) => ({
  kpis: {
    inProgress: 5,
    inQueue: 2,
    inQueueUnfiltered: 3,
    longestWaitMinutes: 45,
    longestWaitWindowDays: 30,
    staleInQueue: 0,
    agentsOnline: 2,
    agentsTotal: 3,
    avgLoad: 2.5,
  },
  queueByTeam: [
    { id: 4, name: 'Suporte', inQueue: 2, inProgress: 5, agentsOnline: 2 },
  ],
  conversations: {
    items: [
      {
        id: 101,
        contactName: 'Maria Lima',
        contactPhone: '+55 11 99999-0000',
        agentName: 'Ana Souza',
        inboxName: 'WhatsApp',
        channelType: 'Channel::Whatsapp',
        labels: [],
        priority: 'high',
        durationMinutes: 12,
        lastMessageMinutes: 3,
        status: 'atendendo',
      },
    ],
    counts: { all: 7, naFila: 2, atendendo: 4, aguardando: 1 },
    pagination: { page: 1, perPage: 1, totalCount: 2, totalPages: 2 },
  },
  agents: [{ id: 1, name: 'Ana Souza', status: 'online', load: 3 }],
  alerts: [
    {
      id: 202,
      contactName: 'Espera Longa',
      minutes: 22,
      inboxName: 'Email',
      labels: [],
    },
  ],
  ...overrides,
});

const respondWith = overrides =>
  getSupervisor.mockResolvedValue(payload(overrides));

const mountScreen = async () => {
  const wrapper = mount(MonitoramentoSupervisor);
  await flushPromises();
  return wrapper;
};

const paramsOfLastCall = () => getSupervisor.mock.calls.at(-1)[0];

const tile = (wrapper, label) =>
  wrapper.findAll('dl > div').find(node => node.text().includes(label));

const agentTypeButton = (wrapper, label) =>
  wrapper.findAll('button').find(node => node.text() === label);

describe('MonitoramentoSupervisor', () => {
  beforeEach(() => {
    getSupervisor.mockReset();
    respondWith();
  });

  it('shows the top KPIs from the live snapshot', async () => {
    const wrapper = await mountScreen();

    expect(tile(wrapper, 'In progress').text()).toContain('5');
    expect(tile(wrapper, 'In queue').text()).toContain('2');
    expect(tile(wrapper, 'Agents online').text()).toContain('2/3');
  });

  it('filters by team', async () => {
    const wrapper = await mountScreen();
    const teamSelect = wrapper.find('select');

    await teamSelect.setValue('4');
    await flushPromises();

    expect(String(paramsOfLastCall().teamId)).toBe('4');
  });

  it('switches between all, human and bot, and resets back to page 1', async () => {
    const wrapper = await mountScreen();

    // Vai para a pagina 2 antes de trocar o filtro.
    wrapper.findComponent(PaginationFooter).vm.$emit('update:currentPage', 2);
    await flushPromises();
    expect(paramsOfLastCall().page).toBe(2);

    await agentTypeButton(wrapper, 'AI').trigger('click');
    await flushPromises();

    expect(paramsOfLastCall().agentType).toBe('bot');
    // Pagina 3 de um recorte que agora pode ter so 1 pagina mostraria uma
    // tabela vazia por engano.
    expect(paramsOfLastCall().page).toBe(1);
    expect(agentTypeButton(wrapper, 'AI').attributes('aria-pressed')).toBe(
      'true'
    );
  });

  it('changes the status_filter when a table chip is picked', async () => {
    const wrapper = await mountScreen();

    // Emite direto o contrato do TabBar (o `tab` inteiro) em vez de simular o
    // clique: o mapeamento clique -> indice e responsabilidade do proprio
    // TabBar, ja coberto pela story dele -- aqui interessa que a tela traduz
    // a escolha para o filtro certo.
    wrapper
      .findComponent(TabBar)
      .vm.$emit('tabChanged', { value: 'aguardando' });
    await flushPromises();

    expect(paramsOfLastCall().statusFilter).toBe('aguardando');
  });

  it('asks for the next page', async () => {
    const wrapper = await mountScreen();

    wrapper.findComponent(PaginationFooter).vm.$emit('update:currentPage', 2);
    await flushPromises();

    expect(paramsOfLastCall().page).toBe(2);
  });

  it('keeps the numbers on screen when a background refresh fails', async () => {
    const wrapper = await mountScreen();
    expect(wrapper.text()).toContain('Ana Souza');

    getSupervisor.mockRejectedValueOnce(new Error('Request failed with 500'));
    // Uma troca de filtro dispara o mesmo `fetch` que o auto-refresh chamaria.
    await wrapper.find('select').setValue('4');
    await flushPromises();

    expect(wrapper.text()).toContain('Ana Souza');
    expect(wrapper.text()).not.toContain('Could not load the report');
  });

  it('shows a translated message when the first load fails', async () => {
    getSupervisor.mockRejectedValue(new Error('Request failed with 500'));
    const wrapper = await mountScreen();

    expect(wrapper.text()).toContain('Could not load the report');
    expect(wrapper.text()).not.toContain('500');
  });

  it('cancels the request in flight when the filter changes', async () => {
    let firstSignal;
    getSupervisor.mockImplementationOnce(
      (_params, { signal }) =>
        new Promise((_resolve, reject) => {
          firstSignal = signal;
          signal.addEventListener('abort', () =>
            reject(new DOMException('Aborted', 'AbortError'))
          );
        })
    );
    const wrapper = mount(MonitoramentoSupervisor);

    respondWith({
      agents: [{ id: 9, name: 'Time Suporte', status: 'online', load: 1 }],
    });
    await wrapper.find('select').setValue('4');
    await flushPromises();

    expect(firstSignal.aborted).toBe(true);
    expect(wrapper.text()).toContain('Time Suporte');
    expect(wrapper.text()).not.toContain('Could not load the report');
  });
});
