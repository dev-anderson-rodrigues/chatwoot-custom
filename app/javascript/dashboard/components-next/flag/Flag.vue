<script setup>
import { h } from 'vue';

const props = defineProps({
  country: { type: String, required: true },
  squared: { type: Boolean, default: false },
});

const renderFlag = () => {
  const classes = ['fi', `fi-${props.country.toLowerCase()}`, 'flex-shrink-0'];
  if (props.squared) {
    classes.push('fis');
  }
  return h('span', { class: classes });
};
</script>

<template>
  <component :is="renderFlag" />
</template>

<!--
  [FORK] O `@import 'flag-icons/css/flag-icons.min.css'` que ficava aqui foi
  movido para uma tag <link> em app/views/layouts/vueapp.html.erb, apontando
  para public/flag-icons/.

  Motivo: esse CSS tem 540 `url()` para SVGs, e cada uma vira uma resolucao de
  asset individual no Vite. Em dev, sobre o bind mount 9p do Docker Desktop no
  Windows, esse modulo simplesmente nunca terminava de compilar (medido: 765s e
  1062s sem completar) -- e como Flag.vue esta no grafo do entrypoint do
  dashboard, ele travava a aplicacao inteira em tela branca. Para comparacao, os
  outros 3.582 modulos do dashboard carregam em 122s sem uma falha.

  Servido como asset estatico o CSS sai do pipeline do Vite: as bandeiras
  continuam identicas, e o build de producao ainda economiza as 540 resolucoes.
-->
