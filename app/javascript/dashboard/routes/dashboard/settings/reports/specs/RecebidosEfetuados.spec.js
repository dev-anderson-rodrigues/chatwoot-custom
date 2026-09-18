import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { withFullI18n } from 'test-i18n';
import RecebidosEfetuados from '../RecebidosEfetuados.vue';

withFullI18n();

const getOrigem = vi.fn();
const teams = ref([{ id: 4, name: 'Suporte' }]);

vi.mock('dashboard/api/operationReports', () => ({
  default: {
    getOrigem: (...args) => getOrigem(...args),
  },
  emptyOrigem: () => ({
    summary: { total: 0, recebidos: 0, efetuados: 0, recebidosPct: 0, efetuadosPct: 0 },
    dailyEvolution: [],
    byOrigin: [],
    byTeam: [],
    byInbox: [],
    byAgent: [],
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => teams,
}));

// @chatwoot/viz nao e o alvo deste spec (tem o proprio, LineChart.spec.js) --
// mockado para nao depender de Canvas/ResizeObserver no jsdom.
vi.mock('@chatwoot/viz', () => ({
  LineChart: { name: 'VizLineChart', props: ['data', 'ariaLabel'], template: '<div />' },
}));

// vue-datepicker-next monta um widget de calendario pesado; o contrato que
// importa aqui e o do DateRangePicker (value/change), nao o datepicker em si.
vi.mock('dashboard/components/ui/DateRangePicker.vue', () => ({
  default: {
    name: 'DateRangePicker',
    props: ['value', 'confirmText', 'placeholder'],
    emits: ['change'],
    template: '<button @click="$emit(\'change\', [new Date(\'2026-01-01\'), new Date(\'2026-01-05\')])" />',
  },
}));

const summary = (overrides = {}) => ({
  total: 10,
  recebidos: 6,
  efetuados: 4,
  recebidosPct: 60,
  efetuadosPct: 40,
  ...overrides,
});

const respondWith = (overrides = {}) =>
  getOrigem.mockResolvedValue({
    summary: summary(),
    dailyEvolution: [],
    byOrigin: [],
    byTeam: [],
    byInbox: [],
    byAgent: [],
    ...overrides,
  });

const mountScreen = async () => {
  const wrapper = mount(RecebidosEfetuados);
  await flushPromises();
  return wrapper;
};

const paramsOfLastCall = () => getOrigem.mock.calls.at(-1)[0];

const tile = (wrapper, label) =>
  wrapper.findAll('dl > div').find(node => node.text().includes(label));

const button = (wrapper, label) =>
  wrapper.findAll('button').find(node => node.text() === label);

const windowDays = ({ from, to }) => Math.round((to - from) / 86400);

describe('RecebidosEfetuados', () => {
  beforeEach(() => {
    getOrigem.mockReset();
    respondWith();
  });

  it('shows the summary tiles from the api', async () => {
    const wrapper = await mountScreen();

    expect(tile(wrapper, 'Total in period').text()).toContain('10');
    expect(tile(wrapper, 'Received').text()).toContain('6');
    expect(tile(wrapper, 'Made').text()).toContain('4');
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

  it('shows a translated message when the first load fails', async () => {
    getOrigem.mockRejectedValue(new Error('Request failed with 500'));
    const wrapper = await mountScreen();

    expect(wrapper.text()).toContain('Could not load the data');
    expect(wrapper.text()).not.toContain('500');
  });

  it('shows the error state when a filter change fails, unlike a screen that polls', async () => {
    // Esta tela nao tem useLiveRefresh -- so busca de novo quando o filtro
    // muda, igual Cockpit/Robo e humano. Nelas uma falha apos trocar filtro
    // acende erro (o filtro anterior nao serve mais), diferente do
    // Monitoramento, que atualiza sozinho e por isso ignora falha isolada.
    const wrapper = await mountScreen();
    expect(wrapper.text()).toContain('10');

    getOrigem.mockRejectedValueOnce(new Error('Request failed with 500'));
    await wrapper.find('select').setValue('4');
    await flushPromises();

    expect(wrapper.text()).toContain('Could not load the data');
  });

  it('cancels the request in flight when the filter changes', async () => {
    let firstSignal;
    getOrigem.mockImplementationOnce(
      (_params, { signal }) =>
        new Promise((_resolve, reject) => {
          firstSignal = signal;
          signal.addEventListener('abort', () =>
            reject(new DOMException('Aborted', 'AbortError'))
          );
        })
    );
    const wrapper = mount(RecebidosEfetuados);

    respondWith({ summary: summary({ total: 99 }) });
    await button(wrapper, '7 days').trigger('click');
    await flushPromises();

    expect(firstSignal.aborted).toBe(true);
    expect(wrapper.text()).toContain('99');
    expect(wrapper.text()).not.toContain('Could not load the data');
  });

  it('renders the origin and team breakdowns when present', async () => {
    respondWith({
      byOrigin: [{ key: 'campaign', kind: 'automation', count: 3, pct: 100 }],
      byTeam: [{ id: 4, name: 'Suporte', total: 5, recebidos: 3, efetuados: 2 }],
    });
    const wrapper = await mountScreen();

    expect(wrapper.text()).toContain('Campaign / bulk send');
    expect(wrapper.text()).toContain('Suporte');
  });
});
