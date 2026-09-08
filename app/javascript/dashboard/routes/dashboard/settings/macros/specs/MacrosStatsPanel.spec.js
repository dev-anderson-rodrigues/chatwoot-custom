import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import MacrosStatsPanel from '../MacrosStatsPanel.vue';

withFullI18n();

const fetchStats = vi.fn();

vi.mock('dashboard/api/macros', () => ({
  default: {
    fetchStats: (...args) => fetchStats(...args),
  },
}));

const macroStat = (overrides = {}) => ({
  macro_id: 1,
  macro_name: 'Abrir chamado',
  total: 10,
  counts: { pending: 0, success: 8, partial: 1, failed: 1 },
  success_rate: 80.0,
  last_executed_at: 1756000000,
  ...overrides,
});

const respondWith = payload =>
  fetchStats.mockResolvedValue({ data: { payload } });

const mountPanel = async () => {
  const wrapper = mount(MacrosStatsPanel);
  await flushPromises();
  return wrapper;
};

const paramsOfLastCall = () => fetchStats.mock.calls.at(-1)[0];

const daysBack = iso => Math.round((Date.now() - new Date(iso)) / 86400000);

const tile = (wrapper, label) =>
  wrapper.findAll('dl > div').find(node => node.text().includes(label));

const periodButton = (wrapper, label) =>
  wrapper.findAll('button').find(node => node.text() === label);

describe('MacrosStatsPanel', () => {
  beforeEach(() => {
    fetchStats.mockReset();
    respondWith([macroStat()]);
  });

  it('shows the aggregated numbers of the period', async () => {
    const wrapper = await mountPanel();

    expect(tile(wrapper, 'Runs').text()).toContain('10');
    expect(tile(wrapper, 'Success rate').text()).toContain('80%');
    // Falha e parcial contam juntas: as duas deixaram acao sem rodar.
    expect(tile(wrapper, 'Failures').text()).toContain('2');
    expect(tile(wrapper, 'Macros used').text()).toContain('1');
  });

  it('asks for the last 30 days on mount', async () => {
    await mountPanel();

    expect(daysBack(paramsOfLastCall().from)).toBe(30);
  });

  it('keeps pending runs out of the success rate', async () => {
    respondWith([
      macroStat({
        total: 10,
        counts: { pending: 5, success: 5, partial: 0, failed: 0 },
      }),
    ]);
    const wrapper = await mountPanel();

    // Contar o pendente como fracasso derrubaria a taxa para 50% no meio de um
    // lote grande, so para ela voltar a subir quando o lote terminasse.
    expect(tile(wrapper, 'Success rate').text()).toContain('100%');
    expect(tile(wrapper, 'Runs').text()).toContain('10');
  });

  it('refetches with the chosen period', async () => {
    const wrapper = await mountPanel();
    await periodButton(wrapper, '7 days').trigger('click');
    await flushPromises();

    expect(daysBack(paramsOfLastCall().from)).toBe(7);
    expect(periodButton(wrapper, '7 days').attributes('aria-pressed')).toBe(
      'true'
    );
    expect(periodButton(wrapper, '30 days').attributes('aria-pressed')).toBe(
      'false'
    );
  });

  it('ranks the five most used macros and drops the ones that never ran', async () => {
    respondWith(
      [6, 5, 4, 3, 2, 1, 0].map((total, index) =>
        macroStat({
          macro_id: index + 1,
          macro_name: `Macro ${total}`,
          total,
          counts: { pending: 0, success: total, partial: 0, failed: 0 },
          success_rate: total === 0 ? null : 100,
          last_executed_at: total === 0 ? null : 1756000000,
        })
      )
    );
    const wrapper = await mountPanel();
    const names = wrapper.findAll('li').map(node => node.text());

    expect(names).toHaveLength(5);
    expect(names[0]).toContain('Macro 6');
    expect(names[4]).toContain('Macro 2');
    expect(wrapper.text()).not.toContain('Macro 1');
    expect(wrapper.text()).not.toContain('Macro 0');
    // A macro sem execucao tambem nao entra na contagem de "macros usadas".
    expect(tile(wrapper, 'Macros used').text()).toContain('6');
  });

  it('counts a single run in the singular', async () => {
    respondWith([
      macroStat({
        total: 1,
        counts: { pending: 0, success: 1, partial: 0, failed: 0 },
        success_rate: 100,
      }),
    ]);
    const wrapper = await mountPanel();

    // A chave era texto fixo no plural e a tela mostrava "1 execuções". So
    // apareceu quando o painel foi olhado renderizado, com dado de verdade.
    expect(wrapper.find('li').text()).toContain('1 run');
    expect(wrapper.find('li').text()).not.toContain('1 runs');
  });

  it('shows when each ranked macro last ran', async () => {
    const wrapper = await mountPanel();

    expect(wrapper.find('li').text()).toContain('Last run');
  });

  it('says there is nothing to show when no macro ran in the period', async () => {
    respondWith([
      macroStat({
        total: 0,
        counts: { pending: 0, success: 0, partial: 0, failed: 0 },
        success_rate: null,
        last_executed_at: null,
      }),
    ]);
    const wrapper = await mountPanel();

    expect(wrapper.text()).toContain('No runs in this period');
    expect(wrapper.find('dl').exists()).toBe(false);
  });

  it('shows a translated message when the request fails', async () => {
    fetchStats.mockRejectedValue(new Error('Request failed with 500'));
    const wrapper = await mountPanel();

    expect(wrapper.text()).toContain('Could not load the metrics');
    // O erro cru e detalhe de infraestrutura, nao algo para mostrar ao agente.
    expect(wrapper.text()).not.toContain('500');
  });

  it('names the period group after what it controls, not after the section', async () => {
    const wrapper = await mountPanel();
    const label = wrapper.find('[role="group"]').attributes('aria-label');

    // Um grupo chamado "Overview" dentro de uma secao chamada "Overview" nao
    // diz ao leitor de tela que ali se escolhe o periodo.
    expect(label).toBe('Period');
  });

  it('keeps the previous numbers on screen while the new period loads', async () => {
    const wrapper = await mountPanel();
    fetchStats.mockImplementationOnce(() => new Promise(() => {}));
    await periodButton(wrapper, '7 days').trigger('click');
    await flushPromises();

    const content = wrapper.find('dl').element.parentElement;
    expect(tile(wrapper, 'Runs').text()).toContain('10');
    expect(content.classList.contains('opacity-50')).toBe(true);
  });

  it('ignores a stale response that lands after a newer one', async () => {
    let resolveFirst;
    fetchStats.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveFirst = resolve;
        })
    );
    const wrapper = mount(MacrosStatsPanel);

    respondWith([macroStat({ macro_name: 'Sete dias', total: 7 })]);
    await periodButton(wrapper, '7 days').trigger('click');
    await flushPromises();

    resolveFirst({
      data: { payload: [macroStat({ macro_name: 'Trinta dias', total: 30 })] },
    });
    await flushPromises();

    expect(wrapper.text()).toContain('Sete dias');
    expect(wrapper.text()).not.toContain('Trinta dias');
  });
});
