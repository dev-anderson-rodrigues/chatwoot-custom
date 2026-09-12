import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { withFullI18n } from 'test-i18n';
import CockpitAtendentes from '../CockpitAtendentes.vue';

withFullI18n();

const getCockpitAtendentes = vi.fn();
const teams = ref([{ id: 4, name: 'Suporte' }]);

vi.mock('dashboard/api/operationReports', () => ({
  default: {
    getCockpitAtendentes: (...args) => getCockpitAtendentes(...args),
  },
  emptyTotals: () => ({
    agentsTotal: 0,
    agentsOnline: 0,
    agentsBusy: 0,
    agentsOffline: 0,
    conversationsTotal: 0,
    avgHandleSeconds: 0,
    avgCsat: 0,
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => teams,
}));

// Formato de dominio: quem traduz o snake_case da API e o service, e isso tem
// spec proprio em api/specs/operationReports.spec.js.
const agent = (overrides = {}) => ({
  id: 1,
  rank: 1,
  name: 'Ana Souza',
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
  ...overrides,
});

const totals = (overrides = {}) => ({
  agentsTotal: 1,
  agentsOnline: 1,
  agentsBusy: 0,
  agentsOffline: 0,
  conversationsTotal: 12,
  avgHandleSeconds: 3600,
  avgCsat: 4.5,
  ...overrides,
});

const respondWith = (agents, extraTotals = {}) =>
  getCockpitAtendentes.mockResolvedValue({
    agents,
    totals: totals(extraTotals),
  });

const mountScreen = async () => {
  const wrapper = mount(CockpitAtendentes);
  await flushPromises();
  return wrapper;
};

const paramsOfLastCall = () => getCockpitAtendentes.mock.calls.at(-1)[0];

// Medir o tamanho da janela, nao o deslocamento a partir de agora: a janela
// comeca no inicio do dia, entao o deslocamento varia com a hora em que o teste
// roda e o de 30 dias oscila entre 29 e 30.
const windowDays = ({ from, to }) => Math.round((to - from) / 86400);

const tile = (wrapper, label) =>
  wrapper.findAll('dl > div').find(node => node.text().includes(label));

const periodButton = (wrapper, label) =>
  wrapper.findAll('button').find(node => node.text() === label);

describe('CockpitAtendentes', () => {
  beforeEach(() => {
    getCockpitAtendentes.mockReset();
    respondWith([agent()]);
  });

  it('shows the aggregated numbers of the period', async () => {
    const wrapper = await mountScreen();

    expect(tile(wrapper, 'Agents').text()).toContain('1');
    expect(tile(wrapper, 'Conversations').text()).toContain('12');
    expect(tile(wrapper, 'Avg CSAT').text()).toContain('4.5');
  });

  it('lists one row per agent with team and volume', async () => {
    const wrapper = await mountScreen();
    const row = wrapper.find('tbody tr');

    expect(row.text()).toContain('Ana Souza');
    expect(row.text()).toContain('ana@exemplo.com');
    expect(row.text()).toContain('Suporte');
    expect(row.text()).toContain('12');
  });

  it('says an agent has no team instead of leaving the cell blank', async () => {
    respondWith([agent({ teamName: null })]);
    const wrapper = await mountScreen();

    expect(wrapper.find('tbody tr').text()).toContain('No team');
  });

  it('says there are no responses instead of showing a made-up score', async () => {
    respondWith([agent({ csat: null, csatResponses: 0 })]);
    const wrapper = await mountScreen();

    expect(wrapper.find('tbody tr').text()).toContain('No responses');
  });

  it('asks for the last 30 days on mount', async () => {
    await mountScreen();

    expect(windowDays(paramsOfLastCall())).toBe(30);
  });

  it('refetches with the chosen period', async () => {
    const wrapper = await mountScreen();
    await periodButton(wrapper, '7 days').trigger('click');
    await flushPromises();

    expect(windowDays(paramsOfLastCall())).toBe(7);
    expect(periodButton(wrapper, '7 days').attributes('aria-pressed')).toBe(
      'true'
    );
  });

  it('switches between counting by opening and by resolution', async () => {
    const wrapper = await mountScreen();
    const dateFieldSelect = wrapper.findAll('select')[0];

    await dateFieldSelect.setValue('resolved');
    await flushPromises();

    // Sao perguntas diferentes: "quantas entraram" x "quantas fechei".
    expect(paramsOfLastCall().dateField).toBe('resolved');
  });

  it('filters by team', async () => {
    const wrapper = await mountScreen();
    const teamSelect = wrapper.findAll('select')[1];

    await teamSelect.setValue('4');
    await flushPromises();

    expect(String(paramsOfLastCall().teamId)).toBe('4');
  });

  it('shows a translated message when the request fails', async () => {
    getCockpitAtendentes.mockRejectedValue(
      new Error('Request failed with 500')
    );
    const wrapper = await mountScreen();

    expect(wrapper.text()).toContain('Could not load the cockpit');
    // O erro cru e detalhe de infraestrutura, nao algo para mostrar ao agente.
    expect(wrapper.text()).not.toContain('500');
  });

  it('shows the error state when the window is refused by the api', async () => {
    // O backend devolve 422 quando a janela nao chega inteira. Antes disso a
    // tela mostrava "nenhum dado", que e outra historia.
    getCockpitAtendentes.mockRejectedValue({
      response: { status: 422, data: { error: 'invalid time window' } },
    });
    const wrapper = await mountScreen();

    expect(wrapper.text()).toContain('Could not load the cockpit');
  });

  it('cancels the request in flight when the filter changes', async () => {
    let firstSignal;
    getCockpitAtendentes.mockImplementationOnce(
      (_params, { signal }) =>
        new Promise((_resolve, reject) => {
          firstSignal = signal;
          // E o que o axios faz quando o signal dispara: rejeita.
          signal.addEventListener('abort', () =>
            reject(new DOMException('Aborted', 'AbortError'))
          );
        })
    );
    const wrapper = mount(CockpitAtendentes);

    respondWith([agent({ name: 'Sete dias' })]);
    await periodButton(wrapper, '7 days').trigger('click');
    await flushPromises();

    expect(firstSignal.aborted).toBe(true);
    expect(wrapper.text()).toContain('Sete dias');
    // Requisicao cancelada nao vira estado de erro na tela.
    expect(wrapper.text()).not.toContain('Could not load the cockpit');
  });
});
