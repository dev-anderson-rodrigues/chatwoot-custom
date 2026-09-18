import { computed, reactive, ref } from 'vue';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import operationReportsAPI, {
  emptyOwnership,
} from 'dashboard/api/operationReports';
import { useReportPeriod, PERIOD_OPTIONS } from './useReportPeriod';

export { PERIOD_OPTIONS };

// Devolvido pelo `run` quando a requisicao foi cancelada por uma mais nova.
const SUPERSEDED = Symbol('superseded');

/**
 * [Onda 5 / fatia 1] Resumo de robo x humano.
 *
 * A tela recebe os numeros ja normalizados pelo service e as comparacoes ja
 * calculadas: componente so apresenta.
 */
export function useOwnershipReport() {
  const current = ref(emptyOwnership());
  const previous = ref(emptyOwnership());
  const hasError = ref(false);
  const loaded = ref(false);

  const filters = reactive({ period: '30d', customRange: [] });

  const { range } = useReportPeriod(filters);
  const { run, isPending: loading } = useAbortableRequest();

  const fetch = async () => {
    hasError.value = false;

    try {
      const result = await run(
        signal =>
          operationReportsAPI.getOwnershipSummary(range.value, { signal }),
        { onAbort: SUPERSEDED }
      );

      if (result === SUPERSEDED) return;

      current.value = result.current;
      previous.value = result.previous;
      loaded.value = true;
    } catch (error) {
      current.value = emptyOwnership();
      previous.value = emptyOwnership();
      hasError.value = true;
    }
  };

  const setPeriod = period => {
    filters.period = period;
    fetch();
  };

  const totalResolutions = computed(
    () => current.value.botResolutions + current.value.humanResolutions
  );

  // Quanto do que foi encerrado saiu sem humano nenhum. Zero resolucao nao vira
  // 0% -- "nao houve atendimento" e outra coisa, e a tela mostra tracinho.
  const botShare = computed(() => {
    if (!totalResolutions.value) return null;

    return Math.round(
      (current.value.botResolutions / totalResolutions.value) * 100
    );
  });

  /**
   * Variacao contra o periodo anterior, em pontos percentuais arredondados.
   * Devolve null quando nao havia base de comparacao: crescer "infinito%" a
   * partir de zero nao informa nada.
   */
  const variationOf = campo =>
    computed(() => {
      const antes = previous.value[campo];
      const agora = current.value[campo];
      if (!antes) return null;

      return Math.round(((agora - antes) / antes) * 100);
    });

  const isEmpty = computed(
    () =>
      loaded.value && totalResolutions.value === 0 && !current.value.handoffs
  );

  return {
    current,
    previous,
    loading,
    // A tela usa isto para decidir entre spinner e numeros esmaecidos: depois da
    // primeira carga, trocar filtro nao pode apagar o que ja esta na tela.
    loaded,
    hasError,
    filters,
    isEmpty,
    range,
    totalResolutions,
    botShare,
    variationOf,
    fetch,
    setPeriod,
  };
}
