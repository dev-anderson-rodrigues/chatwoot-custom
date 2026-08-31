<script setup>
import { ref } from 'vue';
import MacroInputFieldsBuilder from './MacroInputFieldsBuilder.vue';

// Story existe para conferir o componente renderizado sem subir o dashboard
// inteiro. Rodar com: pnpm story:dev (porta 6179).

const empty = ref([]);

const populated = ref([
  {
    key: 'cpf',
    label: 'CPF do cliente',
    type: 'cpf',
    required: true,
    placeholder: '000.000.000-00',
    default_value: '',
  },
  {
    key: 'motivo',
    label: 'Motivo do contato',
    type: 'select',
    required: false,
    placeholder: '',
    default_value: '',
    options: [
      { value: 'cobranca', label: 'Cobrança' },
      { value: 'suporte', label: 'Suporte' },
    ],
  },
  {
    key: 'contrato',
    label: 'Contrato',
    type: 'lookup',
    required: false,
    placeholder: '',
    default_value: '',
    lookup_url: 'https://api.exemplo.com/contratos',
    value_key: 'id',
    label_key: 'nome',
    multi: true,
    depends_on: ['cpf'],
  },
]);

const withErrors = ref([
  { key: 'CPF Cliente', label: '', type: 'text' },
  { key: 'cpf', label: 'Documento', type: 'select', options: [] },
  { key: 'cpf', label: 'Contrato', type: 'lookup', lookup_url: '', depends_on: [] },
]);

const errors = {
  input_field_0: { key: 'KEY_INVALID', label: 'LABEL_REQUIRED' },
  input_field_1: { options: 'OPTIONS_REQUIRED' },
  input_field_2: {
    key: 'KEY_DUPLICATED',
    lookup_url: 'LOOKUP_URL_REQUIRED',
    depends_on: 'DEPENDS_ON_REQUIRED',
  },
};
</script>

<template>
  <Story
    title="Settings/Macros/MacroInputFieldsBuilder"
    :layout="{ type: 'single', iframe: true }"
  >
    <Variant title="Vazio">
      <div class="p-6 bg-n-background">
        <MacroInputFieldsBuilder v-model="empty" />
      </div>
    </Variant>

    <Variant title="Com os tres tipos">
      <div class="p-6 bg-n-background">
        <MacroInputFieldsBuilder v-model="populated" />
      </div>
    </Variant>

    <Variant title="Com erros de validacao">
      <div class="p-6 bg-n-background">
        <MacroInputFieldsBuilder v-model="withErrors" :errors="errors" />
      </div>
    </Variant>

    <Variant title="Somente leitura">
      <div class="p-6 bg-n-background">
        <MacroInputFieldsBuilder v-model="populated" read-only />
      </div>
    </Variant>

    <!-- O card vive dentro da area de fundo pontilhado do flow builder; e
         justamente esse contraste que precisa de olho. -->
    <Variant title="Sobre o fundo do editor de macro">
      <div
        class="p-6 macro-gradient-radial dark:macro-dark-gradient-radial macro-gradient-radial-size"
      >
        <MacroInputFieldsBuilder v-model="populated" />
      </div>
    </Variant>
  </Story>
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
