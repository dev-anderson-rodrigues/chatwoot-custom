<script setup>
import { computed } from 'vue';

/**
 * [Onda 5] Tile de métrica dos relatórios de operação.
 *
 * Por que não o `ReportMetricCard.vue` do upstream, que é o vizinho óbvio:
 * ele não tem variação percentual, exige `infoText` (o padrão dele é uma
 * explicação em tooltip por métrica, e as nossas telas usam uma nota única
 * embaixo do grid) e renderiza `<h3>/<h4>` soltos, sem a semântica de lista de
 * definição. Estender o componente do upstream resolveria as três coisas, mas
 * ele é arquivo deles: editar custa conflito em todo sync, que é justamente a
 * estratégia registrada em docs-fork/sincronizar-com-upstream.md.
 *
 * Então o fork tem o seu, e é UM só — a alternativa real aqui não era "reusar o
 * do upstream", era repetir a mesma marcação em cinco telas.
 *
 * A raiz é uma `<div>` para viver dentro de um `<dl>` da tela (HTML5 permite
 * `<div>` agrupando `<dt>/<dd>`).
 */
const props = defineProps({
  label: { type: String, required: true },
  value: { type: [String, Number], required: true },
  // Variação contra o período anterior, em pontos percentuais. `null` esconde:
  // crescer a partir de zero não tem percentual que signifique algo.
  variation: { type: Number, default: null },
  // Como ler a variação. `neutral` é o padrão de propósito: em boa parte das
  // métricas (volume humano, transferências) subir não é bom nem ruim, e pintar
  // de verde ou vermelho seria opinião disfarçada de dado.
  variationMeaning: {
    type: String,
    default: 'neutral',
    validator: valor =>
      ['up-is-good', 'down-is-good', 'neutral'].includes(valor),
  },
  variationTitle: { type: String, default: '' },
  // Linha curta embaixo do valor (ex. "45% · cliente procurou a empresa").
  // Vazio esconde -- nem toda tela precisa de uma segunda linha.
  description: { type: String, default: '' },
});

const hasVariation = computed(() => props.variation !== null);

const variationText = computed(
  () => `${props.variation > 0 ? '+' : ''}${props.variation}%`
);

const variationClass = computed(() => {
  if (props.variationMeaning === 'neutral') return 'text-n-slate-11';

  const bom =
    props.variationMeaning === 'up-is-good'
      ? props.variation > 0
      : props.variation < 0;

  return bom ? 'text-n-teal-11' : 'text-n-ruby-11';
});
</script>

<template>
  <div class="flex flex-col p-3 border rounded-lg border-n-weak bg-n-alpha-1">
    <dt class="text-xs tracking-wide uppercase text-n-slate-11">
      {{ label }}
    </dt>
    <dd
      class="flex items-baseline gap-2 m-0 mt-1 text-2xl font-semibold tabular-nums text-n-slate-12"
    >
      {{ value }}
      <span
        v-if="hasVariation"
        class="text-xs font-medium tabular-nums"
        :class="variationClass"
        :title="variationTitle"
      >
        {{ variationText }}
      </span>
    </dd>
    <p v-if="description" class="m-0 mt-1 text-xs text-n-slate-10">
      {{ description }}
    </p>
  </div>
</template>
