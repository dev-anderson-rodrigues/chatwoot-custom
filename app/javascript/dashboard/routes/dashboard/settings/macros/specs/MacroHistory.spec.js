import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { withFullI18n } from 'test-i18n';
import MacroHistory from '../MacroHistory.vue';

withFullI18n();

const fetchExecutions = vi.fn();
const dispatch = vi.fn();
const agents = ref([{ id: 3, name: 'Ana', available_name: 'Ana Souza' }]);

vi.mock('dashboard/api/macros', () => ({
  default: {
    fetchExecutions: (...args) => fetchExecutions(...args),
  },
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: () => agents,
}));

const execution = (overrides = {}) => ({
  id: 1,
  macro_id: 7,
  conversation_display_id: 42,
  status: 'success',
  inputs: { cpf: '12345678900' },
  error_message: null,
  actions_run: 3,
  actions_total: 3,
  created_at: 1756000000,
  user: { id: 3, name: 'Ana', available_name: 'Ana Souza' },
  ...overrides,
});

const respondWith = (payload, total = payload.length) =>
  fetchExecutions.mockResolvedValue({ data: { payload, meta: { total } } });

const mountHistory = async () => {
  const wrapper = mount(MacroHistory, { props: { macroId: 7 } });
  await flushPromises();
  return wrapper;
};

const paramsOfLastCall = () => fetchExecutions.mock.calls.at(-1)[1];

// Ordem dos selects no filtro: status, depois agente.
const statusSelect = wrapper => wrapper.findAll('select')[0];

describe('MacroHistory', () => {
  beforeEach(() => {
    fetchExecutions.mockReset();
    dispatch.mockReset();
    respondWith([execution()]);
  });

  it('lists a run with its agent, conversation, status and actions ratio', async () => {
    const wrapper = await mountHistory();
    const row = wrapper.find('tbody tr');

    expect(row.text()).toContain('Ana Souza');
    expect(row.text()).toContain('#42');
    expect(row.text()).toContain('Success');
    expect(row.text()).toContain('3 of 3');
  });

  it('asks for the first page on mount', async () => {
    await mountHistory();

    expect(paramsOfLastCall()).toMatchObject({ limit: 20, offset: 0 });
  });

  it('shows the empty message when no run matches', async () => {
    respondWith([], 0);
    const wrapper = await mountHistory();

    expect(wrapper.text()).toContain('No runs match the current filters');
  });

  it('shows a translated message when the request fails', async () => {
    fetchExecutions.mockRejectedValue(new Error('Request failed with 500'));
    const wrapper = await mountHistory();

    expect(wrapper.text()).toContain('Could not load the history');
    // O erro cru e detalhe de infraestrutura, nao algo para mostrar ao agente.
    expect(wrapper.text()).not.toContain('500');
  });

  it('filters by status', async () => {
    const wrapper = await mountHistory();
    await statusSelect(wrapper).setValue('failed');
    await flushPromises();

    expect(paramsOfLastCall()).toMatchObject({ status: 'failed' });
  });

  it('sends the end of the day for the "to" filter', async () => {
    const wrapper = await mountHistory();
    await wrapper.find('#macro-history-to').setValue('2026-09-05');
    await flushPromises();

    // Uma data crua vira meia-noite no backend (`created_at <= to`) e esconderia
    // tudo o que rodou no proprio dia escolhido.
    expect(paramsOfLastCall()).toMatchObject({ to: '2026-09-05T23:59:59' });
  });

  it('goes back to the first page when a filter changes', async () => {
    respondWith([execution()], 60);
    const wrapper = await mountHistory();

    wrapper
      .findComponent({ name: 'PaginationFooter' })
      .vm.$emit('update:currentPage', 3);
    await flushPromises();
    expect(paramsOfLastCall()).toMatchObject({ offset: 40 });

    await statusSelect(wrapper).setValue('failed');
    await flushPromises();
    expect(paramsOfLastCall()).toMatchObject({ offset: 0, status: 'failed' });
  });

  it('hides pagination while everything fits on one page', async () => {
    respondWith([execution()], 1);
    const wrapper = await mountHistory();

    expect(wrapper.findComponent({ name: 'PaginationFooter' }).exists()).toBe(
      false
    );
  });

  it('reveals the inputs of a run when expanded', async () => {
    const wrapper = await mountHistory();
    expect(wrapper.text()).not.toContain('12345678900');

    await wrapper.find('tbody button').trigger('click');

    expect(wrapper.text()).toContain('cpf');
    expect(wrapper.text()).toContain('12345678900');
  });

  it('says so when a run had no inputs', async () => {
    respondWith([execution({ inputs: {} })]);
    const wrapper = await mountHistory();
    await wrapper.find('tbody button').trigger('click');

    expect(wrapper.text()).toContain('This macro has no input fields');
  });

  it('shows the error of a failed run only when there is one', async () => {
    respondWith([
      execution({
        status: 'failed',
        error_message: 'assign_team: team not found',
        actions_run: 1,
        actions_total: 3,
      }),
    ]);
    const wrapper = await mountHistory();
    await wrapper.find('tbody button').trigger('click');

    expect(wrapper.text()).toContain('assign_team: team not found');
    expect(wrapper.text()).toContain('1 of 3');
  });

  it('ignores a stale response that lands after a newer one', async () => {
    let resolveFirst;
    fetchExecutions.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveFirst = resolve;
        })
    );
    const wrapper = mount(MacroHistory, { props: { macroId: 7 } });

    respondWith([execution({ id: 2, conversation_display_id: 99 })]);
    await statusSelect(wrapper).setValue('failed');
    await flushPromises();

    resolveFirst({
      data: {
        payload: [execution({ conversation_display_id: 11 })],
        meta: { total: 1 },
      },
    });
    await flushPromises();

    expect(wrapper.text()).toContain('#99');
    expect(wrapper.text()).not.toContain('#11');
  });
});
