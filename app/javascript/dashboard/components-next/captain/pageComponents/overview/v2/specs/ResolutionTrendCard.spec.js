import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import ResolutionTrendCard from '../ResolutionTrendCard.vue';

// @chatwoot/viz e mockado (Canvas/ResizeObserver nao existem no jsdom), mas a
// logica de formatacao de data (formatDate/formatDay/bucketLabel) e deste
// componente, nao da lib -- continua exercitada de verdade por este spec.
vi.mock('@chatwoot/viz', () => ({
  LineChart: { name: 'VizLineChart', props: ['data'], template: '<div />' },
  BarChart: { name: 'VizBarChart', props: ['data'], template: '<div />' },
}));

const trend = {
  buckets: [
    {
      starts_on: '2026-01-05',
      ends_on: '2026-01-05',
      conversations_handled: 3,
      resolved_by_captain: 1,
    },
    {
      starts_on: '2026-01-06',
      ends_on: '2026-01-06',
      conversations_handled: 2,
      resolved_by_captain: 2,
    },
  ],
};

describe('ResolutionTrendCard.vue', () => {
  const globalConfig = {
    global: {
      stubs: {
        OverviewPanel: {
          template: '<div><slot /><slot name="actions" /></div>',
        },
      },
    },
  };

  // Regressao: `locale.value` do vue-i18n vem como "pt_BR" (underscore), e
  // `new Intl.DateTimeFormat('pt_BR', ...)` lanca RangeError -- o mesmo bug
  // corrigido em OrigemDailyEvolutionChart.vue (ver aquele spec). Este
  // componente tinha a mesma chamada crua a `locale.value` sem passar por
  // `useLocale()`.
  it.each(['pt_BR', 'en'])(
    'renders the resolution trend chart without throwing for locale %s',
    async locale => {
      withFullI18n(locale);

      const wrapper = mount(ResolutionTrendCard, {
        props: { trend },
        ...globalConfig,
      });

      expect(wrapper.findComponent({ name: 'VizLineChart' }).exists()).toBe(
        true
      );
    }
  );
});
