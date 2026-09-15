import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import FilaDailyEvolutionCharts from '../FilaDailyEvolutionCharts.vue';

// @chatwoot/viz e mockado (Canvas/ResizeObserver nao existem no jsdom), mas a
// logica de formatacao de data (formatDate) e deste componente, nao da lib --
// continua exercitada de verdade por este spec.
vi.mock('@chatwoot/viz', () => ({
  LineChart: { name: 'VizLineChart', props: ['data'], template: '<div />' },
  BarChart: { name: 'VizBarChart', props: ['data'], template: '<div />' },
}));

const dailyEvolution = [
  { date: '2026-01-05', volume: 3, avg_wait_minutes: 4.5 },
  { date: '2026-01-06', volume: 2, avg_wait_minutes: 6.2 },
].map(row => ({
  date: row.date,
  volume: row.volume,
  avgWaitMinutes: row.avg_wait_minutes,
}));

describe('FilaDailyEvolutionCharts.vue', () => {
  // Regressao: `locale.value` do vue-i18n vem como "pt_BR" (underscore), e
  // `new Intl.DateTimeFormat('pt_BR', ...)` lanca RangeError -- mesmo bug
  // corrigido em OrigemDailyEvolutionChart.vue (fatia 3), so pego na
  // verificacao visual porque os specs mockavam @chatwoot/viz inteiro.
  it.each(['pt_BR', 'en'])(
    'renders both charts without throwing for locale %s',
    async locale => {
      withFullI18n(locale);

      const wrapper = mount(FilaDailyEvolutionCharts, {
        props: { dailyEvolution },
      });

      expect(wrapper.findComponent({ name: 'VizBarChart' }).exists()).toBe(
        true
      );
      expect(wrapper.findComponent({ name: 'VizLineChart' }).exists()).toBe(
        true
      );
    }
  );

  it('shows the empty state when there is no data', () => {
    withFullI18n('pt_BR');

    const wrapper = mount(FilaDailyEvolutionCharts, {
      props: { dailyEvolution: [] },
    });

    expect(wrapper.findComponent({ name: 'VizBarChart' }).exists()).toBe(false);
    expect(wrapper.findComponent({ name: 'VizLineChart' }).exists()).toBe(
      false
    );
  });
});
