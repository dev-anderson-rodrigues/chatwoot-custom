import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import OrigemDailyEvolutionChart from '../OrigemDailyEvolutionChart.vue';

// @chatwoot/viz e mockado (Canvas/ResizeObserver nao existem no jsdom), mas a
// logica de formatacao de data (formatDate/chartData) e deste componente, nao
// da lib -- continua exercitada de verdade por este spec.
vi.mock('@chatwoot/viz', () => ({
  LineChart: { name: 'VizLineChart', props: ['data'], template: '<div />' },
}));

const dailyEvolution = [
  { date: '2026-01-05', recebidos: 3, efetuados: 1 },
  { date: '2026-01-06', recebidos: 2, efetuados: 4 },
];

describe('OrigemDailyEvolutionChart.vue', () => {
  // Regressao: `locale.value` do vue-i18n vem como "pt_BR" (underscore), e
  // `new Intl.DateTimeFormat('pt_BR', ...)` lanca RangeError -- isso escapava
  // dos specs porque toda a suite roda com locale 'en' (test-i18n padrao) e o
  // @vue/viz mockado escondia o formatDate, que so aparece renderizado numa
  // tela de verdade (ver docs-fork/handoff.md, "verificacao visual acha o que
  // teste nao acha").
  it.each(['pt_BR', 'en'])(
    'renders the daily evolution chart without throwing for locale %s',
    async locale => {
      withFullI18n(locale);

      const wrapper = mount(OrigemDailyEvolutionChart, {
        props: { dailyEvolution },
      });

      expect(wrapper.findComponent({ name: 'VizLineChart' }).exists()).toBe(
        true
      );
    }
  );

  it('shows the empty state when there is no data', () => {
    withFullI18n('pt_BR');

    const wrapper = mount(OrigemDailyEvolutionChart, {
      props: { dailyEvolution: [] },
    });

    expect(wrapper.findComponent({ name: 'VizLineChart' }).exists()).toBe(
      false
    );
  });
});
