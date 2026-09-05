<script>
import { useVuelidate } from '@vuelidate/core';
import { required, url } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';

import NextButton from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import { DASHBOARD_APP_URL_VARIABLES } from 'dashboard/helper/dashboardAppHelper';

export default {
  components: {
    NextButton,
    Checkbox,
  },
  props: {
    show: {
      type: Boolean,
      default: false,
    },
    mode: {
      type: String,
      default: 'create',
    },
    selectedAppData: {
      type: Object,
      default: () => ({}),
    },
  },
  emits: ['close'],
  setup() {
    return { v$: useVuelidate() };
  },
  validations: {
    app: {
      title: { required },
      content: {
        type: { required },
        url: { required, url },
      },
    },
  },
  data() {
    return {
      isLoading: false,
      app: {
        title: '',
        showInSidebar: false,
        pinToSidebar: false,
        content: {
          type: 'frame',
          url: '',
        },
      },
    };
  },
  computed: {
    header() {
      return this.$t(`INTEGRATION_SETTINGS.DASHBOARD_APPS.${this.mode}.HEADER`);
    },
    submitButtonLabel() {
      return this.$t(
        `INTEGRATION_SETTINGS.DASHBOARD_APPS.${this.mode}.FORM_SUBMIT`
      );
    },
    // Sem isto o admin nao tem como descobrir que a URL aceita variaveis. A
    // lista sai do helper que faz a substituicao, para nao divergir dele.
    urlVariablesHint() {
      return this.$t(
        'INTEGRATION_SETTINGS.DASHBOARD_APPS.FORM.URL_VARIABLES_HINT',
        { variables: DASHBOARD_APP_URL_VARIABLES.map(v => `{${v}}`).join(', ') }
      );
    },
  },
  mounted() {
    if (this.mode === 'UPDATE' && this.selectedAppData) {
      this.app.title = this.selectedAppData.title;
      // Copia, nao referencia: `content[0]` e o objeto que vive no store, e
      // editar a URL aqui alterava o registro da lista mesmo se o admin
      // fechasse o modal sem salvar.
      this.app.content = { ...this.selectedAppData.content[0] };
      this.app.showInSidebar = this.selectedAppData.show_in_sidebar || false;
      this.app.pinToSidebar = this.selectedAppData.pin_to_sidebar || false;
    }
  },
  methods: {
    // Fixar um app que nao esta na barra lateral nao significa nada: o item
    // fixado e justamente a entrada de primeiro nivel na barra.
    onToggleShowInSidebar() {
      if (!this.app.showInSidebar) {
        this.app.pinToSidebar = false;
      }
    },
    closeModal() {
      // Reset the data once closed
      this.app = {
        title: '',
        showInSidebar: false,
        pinToSidebar: false,
        content: { type: 'frame', url: '' },
      };
      this.$emit('close');
    },
    async submit() {
      try {
        this.v$.$touch();
        if (this.v$.$invalid) {
          return;
        }

        const action = this.mode.toLowerCase();
        const payload = {
          title: this.app.title,
          show_in_sidebar: this.app.showInSidebar,
          pin_to_sidebar: this.app.pinToSidebar,
          content: [this.app.content],
        };

        if (action === 'update') {
          payload.id = this.selectedAppData.id;
        }

        this.isLoading = true;
        await this.$store.dispatch(`dashboardApps/${action}`, payload);
        useAlert(
          this.$t(
            `INTEGRATION_SETTINGS.DASHBOARD_APPS.${this.mode}.API_SUCCESS`
          )
        );
        this.closeModal();
      } catch (err) {
        useAlert(
          this.$t(`INTEGRATION_SETTINGS.DASHBOARD_APPS.${this.mode}.API_ERROR`)
        );
      } finally {
        this.isLoading = false;
      }
    },
  },
};
</script>

<template>
  <woot-modal :show="show" :on-close="closeModal">
    <div class="flex flex-col h-auto overflow-auto">
      <woot-modal-header :header-title="header" />
      <form class="w-full" @submit.prevent="submit">
        <woot-input
          v-model="app.title"
          :class="{ error: v$.app.title.$error }"
          class="w-full"
          :label="$t('INTEGRATION_SETTINGS.DASHBOARD_APPS.FORM.TITLE_LABEL')"
          :placeholder="
            $t('INTEGRATION_SETTINGS.DASHBOARD_APPS.FORM.TITLE_PLACEHOLDER')
          "
          :error="
            v$.app.title.$error
              ? $t('INTEGRATION_SETTINGS.DASHBOARD_APPS.FORM.TITLE_ERROR')
              : null
          "
          data-testid="app-title"
          @input="v$.app.title.$touch"
          @blur="v$.app.title.$touch"
        />
        <woot-input
          v-model="app.content.url"
          :class="{ error: v$.app.content.url.$error }"
          class="w-full"
          :label="$t('INTEGRATION_SETTINGS.DASHBOARD_APPS.FORM.URL_LABEL')"
          :placeholder="
            $t('INTEGRATION_SETTINGS.DASHBOARD_APPS.FORM.URL_PLACEHOLDER')
          "
          :error="
            v$.app.content.url.$error
              ? $t('INTEGRATION_SETTINGS.DASHBOARD_APPS.FORM.URL_ERROR')
              : null
          "
          data-testid="app-url"
          @input="v$.app.content.url.$touch"
          @blur="v$.app.content.url.$touch"
        />
        <p class="mt-1 mb-3 text-sm text-n-slate-11">
          {{ urlVariablesHint }}
        </p>
        <!-- Label envolvendo o controle: o Checkbox tem uma div na raiz, entao
             um `for` apontando para o id dele nao nomearia campo nenhum. -->
        <label
          class="flex items-center gap-2 mb-2 text-sm cursor-pointer text-n-slate-12"
        >
          <Checkbox
            v-model="app.showInSidebar"
            data-testid="app-show-in-sidebar"
            @change="onToggleShowInSidebar"
          />
          {{ $t('INTEGRATION_SETTINGS.DASHBOARD_APPS.FORM.SHOW_IN_SIDEBAR') }}
        </label>
        <label
          class="flex items-center gap-2 mb-4 text-sm ps-6"
          :class="
            app.showInSidebar
              ? 'cursor-pointer text-n-slate-12'
              : 'cursor-not-allowed text-n-slate-10'
          "
        >
          <Checkbox
            v-model="app.pinToSidebar"
            :disabled="!app.showInSidebar"
            data-testid="app-pin-to-sidebar"
          />
          {{ $t('INTEGRATION_SETTINGS.DASHBOARD_APPS.FORM.PIN_TO_SIDEBAR') }}
          <!-- Dentro do label de proposito: assim o motivo entra no nome
               acessivel do controle. Um `aria-describedby` no Checkbox pousaria
               na div raiz dele, longe do input, e nao seria anunciado. -->
          <span v-if="!app.showInSidebar" class="text-xs text-n-slate-10">
            ({{
              $t(
                'INTEGRATION_SETTINGS.DASHBOARD_APPS.FORM.PIN_TO_SIDEBAR_HINT'
              )
            }})
          </span>
        </label>
        <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
          <NextButton
            faded
            slate
            type="reset"
            :label="
              $t('INTEGRATION_SETTINGS.DASHBOARD_APPS.CREATE.FORM_CANCEL')
            "
            @click.prevent="closeModal"
          />
          <NextButton
            type="submit"
            :label="submitButtonLabel"
            :disabled="v$.$invalid"
            :is-loading="isLoading"
          />
        </div>
      </form>
    </div>
  </woot-modal>
</template>
