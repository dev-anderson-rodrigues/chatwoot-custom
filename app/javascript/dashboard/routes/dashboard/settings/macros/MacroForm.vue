<script>
import { provide } from 'vue';
import MacroNodes from './MacroNodes.vue';
import MacroProperties from './MacroProperties.vue';
import MacroInputFieldsBuilder from './MacroInputFieldsBuilder.vue';
import { required } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import {
  validateActions,
  validateMacroInputFields,
} from 'dashboard/helper/validations';

export default {
  components: {
    MacroNodes,
    MacroProperties,
    MacroInputFieldsBuilder,
  },
  props: {
    macroData: {
      type: Object,
      default: () => ({}),
    },
    canManagePublicMacros: {
      type: Boolean,
      default: true,
    },
    readOnly: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['submit'],
  setup() {
    const v$ = useVuelidate();
    provide('v$', v$);

    return { v$ };
  },
  data() {
    return {
      macro: this.macroData,
      errors: {},
    };
  },
  computed: {
    files() {
      if (this.macro && this.macro.files) return this.macro.files;
      return [];
    },
  },
  watch: {
    $route: {
      handler() {
        this.resetValidation();
      },
      immediate: true,
    },
    macroData: {
      handler() {
        this.macro = this.macroData;
        // Macro criada antes desta feature volta da API sem input_fields.
        if (!this.macro.input_fields) this.macro.input_fields = [];
      },
      immediate: true,
    },
  },
  validations: {
    macro: {
      name: {
        required,
      },
      visibility: {
        required,
      },
    },
  },
  methods: {
    removeObjectProperty(obj, keyToRemove) {
      return Object.fromEntries(
        Object.entries(obj).filter(([key]) => key !== keyToRemove)
      );
    },
    updateName(value) {
      this.macro.name = value;
    },
    updateVisibility(value) {
      this.macro.visibility = value;
    },
    appendNode() {
      this.macro.actions.push({
        action_name: 'assign_team',
        action_params: [],
      });
    },
    deleteNode(index) {
      // remove that index specifically
      // so that the next item does not get marked invalid
      this.errors = this.removeObjectProperty(this.errors, `action_${index}`);
      this.macro.actions.splice(index, 1);
    },
    updateInputFields(value) {
      this.macro.input_fields = value;
      // Limpa os erros dos campos para o agente ver o efeito da correcao sem
      // ter que salvar de novo; a validacao roda inteira no proximo submit.
      this.errors = this.removeInputFieldErrors(this.errors);
    },
    removeInputFieldErrors(errors) {
      return Object.fromEntries(
        Object.entries(errors).filter(
          ([key]) => !key.startsWith('input_field_')
        )
      );
    },
    submit() {
      this.errors = {
        ...validateActions(this.macro.actions),
        ...validateMacroInputFields(this.macro.input_fields),
      };
      if (Object.keys(this.errors).length !== 0) return;

      this.v$.$touch();
      if (this.v$.$invalid) return;

      this.$emit('submit', this.macro);
    },
    resetNode(index) {
      // remove that index specifically
      // so that the next item does not get marked invalid
      this.errors = this.removeObjectProperty(this.errors, `action_${index}`);
      this.macro.actions[index].action_params = [];
    },
    resetValidation() {
      this.errors = {};
      this.v$?.$reset?.();
    },
  },
};
</script>

<template>
  <div class="flex flex-col w-full h-auto lg:flex-row lg:h-full">
    <div
      class="flex-1 w-full h-full max-h-full ltr:pl-12 ltr:pr-6 rtl:pl-6 rtl:pr-12 py-4 overflow-y-auto lg:w-auto macro-gradient-radial dark:macro-dark-gradient-radial macro-gradient-radial-size"
    >
      <div :inert="readOnly" :class="{ 'opacity-75': readOnly }">
        <!-- Os campos vem ANTES do fluxo porque e essa a ordem em que a coisa
             acontece: o agente preenche os campos, e so entao as acoes rodam.
             Ficando depois do "Fim do Fluxo" o bloco contradizia o proprio
             titulo ("Campos pedidos antes de executar"). -->
        <MacroInputFieldsBuilder
          :model-value="macro.input_fields || []"
          :errors="errors"
          :read-only="readOnly"
          class="mb-6 ltr:mr-6 rtl:ml-6"
          @update:model-value="updateInputFields"
        />
        <MacroNodes
          v-model="macro.actions"
          :files="files"
          :errors="errors"
          @add-new-node="appendNode"
          @delete-node="deleteNode"
          @reset-action="resetNode"
        />
      </div>
    </div>
    <div class="w-full lg:w-1/3 pb-4">
      <MacroProperties
        :macro-name="macro.name"
        :macro-visibility="macro.visibility"
        :can-manage-public-macros="canManagePublicMacros"
        :read-only="readOnly"
        @update:name="updateName"
        @update:visibility="updateVisibility"
        @submit="submit"
      />
    </div>
  </div>
</template>

<style scoped>
@tailwind components;

@layer components {
  .macro-gradient-radial {
    background-image: radial-gradient(#ebf0f5 1.2px, transparent 0);
  }

  .macro-dark-gradient-radial {
    background-image: radial-gradient(#293f51 1.2px, transparent 0);
  }

  .macro-gradient-radial-size {
    background-size: 1rem 1rem;
  }
}
</style>
