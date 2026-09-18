import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { withFullI18n } from 'test-i18n';
import FilaHistorico from '../FilaHistorico.vue';

withFullI18n();

const getFilaHistorico = vi.fn();
const teams = ref([{ id: 4, name: 'Suporte' }]);

const emptyKpis = () => ({
  total: 0,
  avgWaitSeconds: 0,
  maxWaitSeconds: 0,
  abandonRate: 0,
  abandonedCount: 0,
});

vi.mock('dashboard/api/operationReports', () => ({
  default: {
    getFilaHistorico: (...args) => getFilaHistorico(...args),
  },
  emptyFilaHistorico: () => ({
    kpis: { current: emptyKpis(), previous: emptyKpis() },
    dailyEvolution: [],
    byTeam: [],
    byAgent: [],
    capacityVsDemand: [],
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => teams,
}));

// @chatwoot/viz nao e o alvo deste spec (tem o proprio,
// FilaDailyEvolutionCharts.spec.js) -- mockado para nao depender de Canvas/
// ResizeObserver no jsdom.
vi.mock('@chatwoot/viz', () => ({
  LineChart: { name: 'VizLineChart', props: ['data'], template: '<div />' },
  BarChart: { name: 'VizBarChart', props: ['data'], template: '<div />' },
}));

// vue-datepicker-next monta um widget de calendario pesado; o contrato que
// importa aqui e o do DateRangePicker (value/change), nao o datepicker em si.
vi.mock('dashboard/components/ui/DateRangePicker.vue', () => ({
  default: {
    name: 'DateRangePicker',
    props: ['value', 'confirmText', 'placeholder'],
    emits: ['change'],
    template:
      "<button @click=\"$emit('change', [new Date('2026-01-01'), new Date('2026-01-05')])\" />",
  },
}));

const kpis = (overrides = {}) => ({ ...emptyKpis(), total: 10, ...overrides });

const respondWith = (overrides = {}) =>
  getFilaHistorico.mockResolvedValue({
    kpis: { current: kpis(), previous: emptyKpis() },
    dailyEvolution: [],
    byTeam: [],
    byAgent: [],
    capacityVsDemand: [],
    ...overrides,
  });

const mountScreen = async () => {
  const wrapper = mount(FilaHistorico);
  await flushPromises();
  return wrapper;
};

const paramsOfLastCall = () => getFilaHistorico.mock.calls.at(-1)[0];

const tile = (wrapper, label) =>
  wrapper.findAll('dl > div').find(node => node.text().includes(label));

const button = (wrapper, label) =>
  wrapper.findAll('button').find(node => node.text() === label);

const windowDays = ({ from, to }) => Math.round((to - from) / 86400);

describe('FilaHistorico', () => {
  beforeEach(() => {
    getFilaHistorico.mockReset();
    respondWith();
  });

  it('shows the KPI tiles from the api', async () => {
    const wrapper = await mountScreen();

    expect(tile(wrapper, 'Total in queue').text()).toContain('10');
  });

  it('asks for the last 30 days on mount', async () => {
    await mountScreen();

    expect(windowDays(paramsOfLastCall())).toBe(30);
  });

  it('refetches with the chosen period', async () => {
    const wrapper = await mountScreen();

    await button(wrapper, '7 days').trigger('click');
    await flushPromises();

    expect(windowDays(paramsOfLastCall())).toBe(7);
    expect(button(wrapper, '7 days').attributes('aria-pressed')).toBe('true');
  });

  it('refetches with a custom range picked from the date picker', async () => {
    const wrapper = await mountScreen();

    await wrapper.findComponent({ name: 'DateRangePicker' }).trigger('click');
    await flushPromises();

    const { from, to } = paramsOfLastCall();
    expect(new Date(from * 1000).getUTCDate()).toBe(1);
    expect(new Date(to * 1000).getUTCDate()).toBe(5);
  });

  it('filters by team', async () => {
    const wrapper = await mountScreen();
    const teamSelect = wrapper.find('select');

    await teamSelect.setValue('4');
    await flushPromises();

    expect(String(paramsOfLastCall().teamId)).toBe('4');
  });

  it('switches between all, human and bot', async () => {
    const wrapper = await mountScreen();

    await button(wrapper, 'AI').trigger('click');
    await flushPromises();

    expect(paramsOfLastCall().agentType).toBe('bot');
    expect(button(wrapper, 'AI').attributes('aria-pressed')).toBe('true');
  });

  it('shows the bot hint on the agent table only when the AI filter is active', async () => {
    const wrapper = await mountScreen();
    expect(wrapper.text()).not.toContain(
      'The AI split considers conversations without an assigned agent'
    );

    await button(wrapper, 'AI').trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain(
      'The AI split considers conversations without an assigned agent'
    );
  });

  it('shows a translated message when the first load fails', async () => {
    getFilaHistorico.mockRejectedValue(new Error('Request failed with 500'));
    const wrapper = await mountScreen();

    expect(wrapper.text()).toContain('Could not load the data');
    expect(wrapper.text()).not.toContain('500');
  });

  it('shows the error state when a filter change fails, unlike a screen that polls', async () => {
    // Esta tela nao tem useLiveRefresh -- so busca de novo quando o filtro
    // muda, igual Origem/Cockpit/Robo e humano. Uma falha apos trocar filtro
    // acende erro porque o filtro anterior nao serve mais.
    const wrapper = await mountScreen();
    expect(wrapper.text()).toContain('10');

    getFilaHistorico.mockRejectedValueOnce(
      new Error('Request failed with 500')
    );
    await wrapper.find('select').setValue('4');
    await flushPromises();

    expect(wrapper.text()).toContain('Could not load the data');
  });

  it('cancels the request in flight when the filter changes', async () => {
    let firstSignal;
    getFilaHistorico.mockImplementationOnce(
      (_params, { signal }) =>
        new Promise((_resolve, reject) => {
          firstSignal = signal;
          signal.addEventListener('abort', () =>
            reject(new DOMException('Aborted', 'AbortError'))
          );
        })
    );
    const wrapper = mount(FilaHistorico);

    respondWith({
      kpis: { current: kpis({ total: 99 }), previous: emptyKpis() },
    });
    await button(wrapper, '7 days').trigger('click');
    await flushPromises();

    expect(firstSignal.aborted).toBe(true);
    expect(wrapper.text()).toContain('99');
    expect(wrapper.text()).not.toContain('Could not load the data');
  });

  it('renders the team and agent tables when present', async () => {
    respondWith({
      byTeam: [
        {
          id: 4,
          name: 'Suporte',
          total: 5,
          avgWaitSeconds: 90,
          maxWaitSeconds: 300,
          abandoned: 1,
        },
      ],
      byAgent: [
        {
          id: 1,
          name: 'Ana',
          total: 3,
          avgWaitSeconds: 60,
          maxWaitSeconds: 120,
          loadPct: 100,
        },
      ],
      capacityVsDemand: [
        {
          id: 4,
          name: 'Suporte',
          demand: 5,
          agents: 1,
          capacity: 5,
          usagePct: 100,
        },
      ],
    });
    const wrapper = await mountScreen();

    expect(wrapper.text()).toContain('Suporte');
    expect(wrapper.text()).toContain('Ana');
  });
});
