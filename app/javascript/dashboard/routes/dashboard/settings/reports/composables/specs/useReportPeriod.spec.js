import { reactive } from 'vue';
import { useReportPeriod, PERIOD_OPTIONS } from '../useReportPeriod';

// Tamanho da janela, nao deslocamento a partir de agora: a janela comeca no
// inicio do dia, entao o deslocamento varia com a hora em que o teste roda.
const windowDays = ({ from, to }) => Math.round((to - from) / 86400);

describe('useReportPeriod', () => {
  it('offers the three shortcuts the reports share', () => {
    expect(PERIOD_OPTIONS).toEqual(['7d', '30d', '90d']);
  });

  it.each([
    ['7d', 7],
    ['30d', 30],
    ['90d', 90],
  ])('turns %s into a window of %i days counting today', (period, days) => {
    const { range } = useReportPeriod(reactive({ period, customRange: [] }));

    expect(windowDays(range.value)).toBe(days);
  });

  it('reacts to the filter changing, without being told to recompute', () => {
    const filters = reactive({ period: '30d', customRange: [] });
    const { range } = useReportPeriod(filters);

    filters.period = '7d';

    expect(windowDays(range.value)).toBe(7);
  });

  it('falls back to 30 days when the period is unknown', () => {
    // Estado impossivel pela tela, mas a URL e o localStorage alcancam o filtro.
    const { range } = useReportPeriod(
      reactive({ period: 'ontem', customRange: [] })
    );

    expect(windowDays(range.value)).toBe(30);
  });

  it('uses the custom range from the first start of day to the last end of day', () => {
    const filters = reactive({
      period: 'custom',
      customRange: [
        new Date('2026-03-01T13:00:00'),
        new Date('2026-03-05T02:00:00'),
      ],
    });
    const { range, isCustomPeriod } = useReportPeriod(filters);

    expect(isCustomPeriod.value).toBe(true);
    expect(windowDays(range.value)).toBe(5);
  });

  it('ignores a half filled custom range instead of sending a broken window', () => {
    const filters = reactive({
      period: 'custom',
      customRange: [new Date('2026-03-01T13:00:00')],
    });
    const { range, isCustomPeriod } = useReportPeriod(filters);

    expect(isCustomPeriod.value).toBe(false);
    expect(windowDays(range.value)).toBe(30);
  });
});
