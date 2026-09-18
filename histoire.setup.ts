import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import { directive as onClickaway } from 'vue3-click-away';
import i18nMessages from 'dashboard/i18n';

// [FORK] histoire.config.ts referencia `setupFile: './histoire.setup.ts'`
// desde o commit que introduziu o Histoire neste projeto (ff5d304541), mas
// o arquivo nunca existiu no historico deste repositorio. Sem ele, o plugin
// interno do Histoire nao consegue resolver o modulo virtual
// `virtual:$histoire-setup` (ver
// node_modules/histoire/dist/node/virtual/vite-plugin.js: `this.resolve(...)`
// falha e cai no branch sem retorno) -- e como toda story importa esse
// modulo virtual na cadeia de coleta, a COLETA de qualquer `.story.vue`
// quebrava, nao so a renderizacao de um componente especifico. E por isso
// nenhuma story deste repo -- nem as triviais como Button.story.vue --
// chegava a aparecer no Histoire.
//
// Este arquivo registra apenas o minimo que os componentes de
// components-next realmente usam fora de uma pagina montada pelo
// entrypoints/dashboard.js real:
//  - i18n: varios componentes chamam useI18n() (Dialog, ComboBox,
//    PhoneNumberInput, o proprio MacroExecuteModal...). Reusa as mesmas
//    mensagens do dashboard para o texto renderizado bater com a aplicacao.
//  - um getter de store, `accounts/isRTL`: TeleportWithDirection.vue chama
//    useMapGetter('accounts/isRTL') para decidir a direcao do conteudo
//    teleportado, e todo Dialog passa por ali.
//  - a diretiva `on-clickaway`: PhoneNumberInput.vue usa `v-on-clickaway`
//    para fechar o dropdown de pais; sem registrar, o Vue avisa
//    `Failed to resolve directive: on-clickaway` e o clique fora nao fecha.
//
// Deliberadamente NAO replica o boot inteiro (router, pinia, Sentry,
// FormKit, FloatingVue, etc.): as stories nao passam por essas
// dependencias, e replicar tudo aumentaria a superficie de manutencao deste
// arquivo sem necessidade.
export function setupVue3({ app }) {
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: i18nMessages,
  });
  app.use(i18n);

  const store = createStore({
    getters: {
      'accounts/isRTL': () => false,
    },
  });
  app.use(store);

  app.directive('on-clickaway', onClickaway);
}
