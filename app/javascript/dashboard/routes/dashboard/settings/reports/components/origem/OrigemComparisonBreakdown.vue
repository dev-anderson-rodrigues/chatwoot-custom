<script setup>
import { computed, ref } from 'vue';

const props = defineProps({
  title: { type: String, required: true },
  hint: { type: String, default: '' },
  items: { type: Array, default: () => [] },
  // So usado quando `item.name` vem nulo (ex. "sem equipe"). Por canal a
  // caixa sempre tem nome (JOIN, nao LEFT JOIN), entao nunca aparece --
  // default seguro em vez de exigir do chamador um rotulo que nunca sera lido.
  noNameLabel: { type: String, default: '—' },
  emptyLabel: { type: String, required: true },
  recebidosLabel: { type: String, required: true },
  efetuadosLabel: { type: String, required: true },
  // `null` = mostra tudo (usado por "Por canal": poucos itens, sem corte).
  // "Por equipe" passa um numero -- a fonte corta em 8 com um "mostrar todos".
  visibleLimit: { type: Number, default: null },
  showAllLabel: { type: String, default: '' },
});

const showAll = ref(false);

const visibleItems = computed(() => {
  if (!props.visibleLimit || showAll.value) return props.items;

  return props.items.slice(0, props.visibleLimit);
});

const hasMore = computed(
  () =>
    props.visibleLimit &&
    props.items.length > props.visibleLimit &&
    !showAll.value
);

const formatCount = value => Number(value).toLocaleString();

// Maior total do conjunto: as barras de cada linha sao relativas a ele, nao
// ao total da propria linha -- assim da para comparar equipes/caixas entre si
// de relance, nao so dentro da mesma linha.
const maxTotal = computed(
  () => props.items.reduce((max, item) => Math.max(max, item.total), 0) || 1
);
</script>

<template>
  <section class="flex flex-col gap-1">
    <h3 class="m-0 text-sm font-medium text-n-slate-12">{{ title }}</h3>
    <p v-if="hint" class="m-0 mb-2 text-xs text-n-slate-10">{{ hint }}</p>

    <p v-if="!items.length" class="m-0 text-sm text-n-slate-11">
      {{ emptyLabel }}
    </p>

    <div v-else class="flex flex-col gap-3">
      <div
        v-for="item in visibleItems"
        :key="item.id ?? 'none'"
        class="flex flex-col gap-1"
      >
        <div class="flex items-center justify-between gap-2">
          <span class="text-sm font-medium truncate text-n-slate-12">
            {{ item.name || noNameLabel }}
          </span>
          <span class="text-xs text-n-slate-10">{{
            formatCount(item.total)
          }}</span>
        </div>
        <div class="flex flex-col gap-0.5">
          <div class="w-full h-1.5 rounded-full bg-n-alpha-2 overflow-hidden">
            <div
              class="h-full rounded-full bg-n-blue-9"
              :style="{ width: `${(item.recebidos / maxTotal) * 100}%` }"
            />
          </div>
          <div class="w-full h-1.5 rounded-full bg-n-alpha-2 overflow-hidden">
            <div
              class="h-full rounded-full bg-n-amber-9"
              :style="{ width: `${(item.efetuados / maxTotal) * 100}%` }"
            />
          </div>
        </div>
        <div class="flex gap-4">
          <span class="text-xs text-n-blue-11"
            >{{ recebidosLabel }} {{ formatCount(item.recebidos) }}</span
          >
          <span class="text-xs text-n-amber-11"
            >{{ efetuadosLabel }} {{ formatCount(item.efetuados) }}</span
          >
        </div>
      </div>

      <button
        v-if="hasMore"
        type="button"
        class="mt-1 text-xs text-left underline text-n-slate-11 hover:text-n-slate-12"
        @click="showAll = true"
      >
        {{ showAllLabel }}
      </button>
    </div>
  </section>
</template>
