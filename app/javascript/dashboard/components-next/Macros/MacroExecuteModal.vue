<script setup>
import { ref, computed, reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, email } from '@vuelidate/validators';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'next/textarea/TextArea.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

// [FORK] Portao de pre-execucao das macros: coleta os `input_fields` que o
// agente precisa preencher antes de a macro rodar. O composable
// useMacroExecution decide quando abrir; aqui so ha o formulario.
//
// Modelado sobre o ConversationResolveAttributesModal, que resolve o mesmo
// problema para os atributos obrigatorios da conversa.

const emit = defineEmits(['submit', 'close']);

const { t } = useI18n();

const dialogRef = ref(null);
const macro = ref(null);
const fields = ref([]);
const values = reactive({});

// Como cada tipo e renderizado. Um mapa, e nao uma cadeia de v-if, porque as
// fatias seguintes trocam entradas daqui: mascara de CPF/CNPJ/telefone e o
// lookup dinamico com depends_on. Hoje esses tres caem no input de texto.
const CONTROL_BY_TYPE = {
  textarea: 'textarea',
  select: 'combobox',
  number: 'number',
  date: 'date',
  email: 'email',
};

const controlFor = field => CONTROL_BY_TYPE[field.type] || 'text';

const rules = computed(() =>
  Object.fromEntries(
    fields.value.map(field => {
      const fieldRules = {};
      if (field.required) fieldRules.required = required;
      if (field.type === 'email') fieldRules.email = email;
      return [field.key, fieldRules];
    })
  )
);

const v$ = useVuelidate(rules, values);

const errorFor = key => {
  const field = v$.value[key];
  if (!field?.$error) return '';

  if (field.email?.$invalid) {
    return t('MACROS.EXECUTE.MODAL.VALIDATIONS.EMAIL');
  }
  return t('MACROS.EXECUTE.MODAL.VALIDATIONS.REQUIRED');
};

const optionsFor = field =>
  (field.options || []).map(({ value, label }) => ({
    value,
    label: label || value,
  }));

// O agente so pode confirmar com os obrigatorios preenchidos. Sem isto o botao
// ficaria ativo e o erro so apareceria depois do clique.
const isComplete = computed(() =>
  fields.value
    .filter(field => field.required)
    .every(field => String(values[field.key] ?? '').trim() !== '')
);

const close = () => dialogRef.value?.close();

const open = (executedMacro, inputFields = []) => {
  macro.value = executedMacro;
  fields.value = inputFields;

  Object.keys(values).forEach(key => delete values[key]);
  inputFields.forEach(field => {
    values[field.key] = field.default_value ?? '';
  });

  v$.value.$reset();
  dialogRef.value?.open();
};

// O Dialog emite `close` tambem quando fechamos apos confirmar. Sem distinguir
// os dois casos, o `close` chegaria ao chamador depois do `submit` e limparia a
// execucao pendente que o portao seguinte -- o de atributos obrigatorios --
// acabou de guardar, deixando o segundo modal sem nada para submeter.
const confirmed = ref(false);

// Fechar aborta a execucao: sem os valores a macro nao tem o que substituir.
const handleClose = () => {
  v$.value.$reset();
  if (confirmed.value) {
    confirmed.value = false;
    return;
  }
  emit('close');
};

const handleConfirm = () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  confirmed.value = true;
  emit('submit', { ...values });
  close();
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="lg"
    :title="macro?.name || t('MACROS.EXECUTE.MODAL.TITLE')"
    :description="t('MACROS.EXECUTE.MODAL.DESCRIPTION')"
    :confirm-button-label="t('MACROS.EXECUTE.MODAL.ACTIONS.RUN')"
    :cancel-button-label="t('MACROS.EXECUTE.MODAL.ACTIONS.CANCEL')"
    :disable-confirm-button="!isComplete"
    @confirm="handleConfirm"
    @close="handleClose"
  >
    <div class="flex flex-col gap-4">
      <div v-for="field in fields" :key="field.key" class="flex flex-col gap-2">
        <!-- O asterisco vem de CSS, nao de texto: assim o leitor de tela nao o
             soletra (o `required` do proprio input ja anuncia a obrigacao) e o
             lint de i18n nao o trata como string a traduzir. -->
        <label
          :for="`macro-input-${field.key}`"
          class="mb-0.5 text-sm font-medium text-n-slate-12"
          :class="{
            'after:content-[\'*\'] after:ml-0.5 after:text-n-ruby-11':
              field.required,
          }"
        >
          {{ field.label || field.key }}
        </label>

        <TextArea
          v-if="controlFor(field) === 'textarea'"
          :id="`macro-input-${field.key}`"
          v-model="values[field.key]"
          class="w-full"
          :required="field.required"
          :placeholder="field.placeholder"
          :message="errorFor(field.key)"
          :message-type="v$[field.key].$error ? 'error' : 'info'"
          @blur="v$[field.key].$touch"
        />

        <ComboBox
          v-else-if="controlFor(field) === 'combobox'"
          :id="`macro-input-${field.key}`"
          v-model="values[field.key]"
          class="w-full"
          :options="optionsFor(field)"
          :required="field.required"
          :placeholder="field.placeholder"
          :message="errorFor(field.key)"
          :message-type="v$[field.key].$error ? 'error' : 'info'"
          :has-error="v$[field.key].$error"
        />

        <Input
          v-else
          :id="`macro-input-${field.key}`"
          v-model="values[field.key]"
          size="md"
          :type="controlFor(field)"
          :required="field.required"
          :placeholder="field.placeholder"
          :message="errorFor(field.key)"
          :message-type="v$[field.key].$error ? 'error' : 'info'"
          @blur="v$[field.key].$touch"
        />
      </div>
    </div>
  </Dialog>
</template>
