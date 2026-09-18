import { computed } from 'vue';
import subDays from 'date-fns/subDays';
import startOfDay from 'date-fns/startOfDay';
import endOfDay from 'date-fns/endOfDay';
import getUnixTime from 'date-fns/getUnixTime';

export const PERIOD_OPTIONS = ['7d', '30d', '90d'];

// O dia de hoje conta: "7 dias" e hoje mais os seis anteriores.
const DAYS_BY_PERIOD = { '7d': 6, '30d': 29, '90d': 89 };

const DEFAULT_PERIOD = '30d';

/**
 * [Onda 5] Janela de tempo dos relatorios de operacao.
 *
 * Todas as telas da onda oferecem os mesmos atalhos (7/30/90 dias) mais um
 * intervalo livre, e todas precisam mandar a janela em unix para a API. Ficar
 * so aqui evita a mesma conta copiada cinco vezes -- foi assim que a fonte
 * acabou com tres formatos diferentes de duracao na tela.
 *
 * Recebe o objeto reativo de filtros da tela, que precisa ter `period` e
 * `customRange`. Nao mexe nesse objeto: quem troca o filtro e o composable do
 * relatorio, que tambem decide quando refazer a busca.
 *
 * @param {{ period: string, customRange: Array }} filters
 * @returns {{ range: import('vue').ComputedRef<{from: number, to: number}>,
 *             isCustomPeriod: import('vue').ComputedRef<boolean> }}
 */
export function useReportPeriod(filters) {
  const isCustomPeriod = computed(
    () => filters.period === 'custom' && filters.customRange?.length === 2
  );

  const range = computed(() => {
    if (isCustomPeriod.value) {
      return {
        from: getUnixTime(startOfDay(filters.customRange[0])),
        to: getUnixTime(endOfDay(filters.customRange[1])),
      };
    }

    const days =
      DAYS_BY_PERIOD[filters.period] ?? DAYS_BY_PERIOD[DEFAULT_PERIOD];

    return {
      from: getUnixTime(startOfDay(subDays(new Date(), days))),
      to: getUnixTime(endOfDay(new Date())),
    };
  });

  return { range, isCustomPeriod };
}
