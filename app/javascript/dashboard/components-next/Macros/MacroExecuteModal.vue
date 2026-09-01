<script setup>
import { ref, computed, reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, email } from '@vuelidate/validators';
import parsePhoneNumber from 'libphonenumber-js';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'next/textarea/TextArea.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import PhoneNumberInput from 'dashboard/components-next/phonenumberinput/PhoneNumberInput.vue';
import { DOCUMENT_HANDLERS } from 'shared/helpers/brazilianDocuments.js';

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

// Como cada tipo e renderizado. Um mapa, e nao uma cadeia de v-if, porque a
// fatia seguinte troca mais uma entrada daqui: o lookup dinamico com
// depends_on. Hoje esse tipo cai no input de texto.
const CONTROL_BY_TYPE = {
  textarea: 'textarea',
  select: 'combobox',
  number: 'number',
  date: 'date',
  email: 'email',
  cpf: 'cpf',
  cnpj: 'cnpj',
  phone: 'phone',
};

const controlFor = field => CONTROL_BY_TYPE[field.type] || 'text';
const isPhoneField = field => controlFor(field) === 'phone';

const rules = computed(() =>
  Object.fromEntries(
    fields.value.map(field => {
      const fieldRules = {};
      if (field.required) fieldRules.required = required;
      if (field.type === 'email') fieldRules.email = email;

      // CPF/CNPJ tem digito verificador, nao so contagem de digitos -- o
      // mesmo helper que a mascara usa. Aceita vazio aqui porque a
      // obrigatoriedade ja e responsabilidade da regra `required` acima.
      const documentHandler = DOCUMENT_HANDLERS[field.type];
      if (documentHandler) {
        fieldRules[field.type] = value =>
          !value || documentHandler.isValid(value);
      }

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
  if (field.cpf?.$invalid) {
    return t('MACROS.EXECUTE.MODAL.VALIDATIONS.CPF');
  }
  if (field.cnpj?.$invalid) {
    return t('MACROS.EXECUTE.MODAL.VALIDATIONS.CNPJ');
  }
  return t('MACROS.EXECUTE.MODAL.VALIDATIONS.REQUIRED');
};

// O valor submetido para CPF/CNPJ vai mascarado ("529.982.247-25"), como na
// fonte Coraxy: e interpolado via {{chave}} tanto em mensagem para o cliente
// quanto em payload de webhook, e mascarado e legivel e trivial de limpar no
// servidor.
const handleDocumentInput = (field, event) => {
  const formatted = DOCUMENT_HANDLERS[field.type].format(event.target.value);

  // O Input e controlado por :model-value -- quando o caractere digitado e
  // descartado pela mascara (uma letra, por exemplo), o valor formatado nao
  // muda, o Vue nao percebe diferenca e nao repinta o DOM, e o caractere
  // descartado fica visivel no campo mesmo fora do valor do modelo. Forca a
  // sincronia direto no elemento para nao deixar lixo na tela.
  if (event.target.value !== formatted) {
    event.target.value = formatted;
  }
  values[field.key] = formatted;
};

const maxLengthFor = field => (field.type === 'cpf' ? 14 : 18);

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

// Bug do PhoneNumberInput: o watcher `immediate` faz parsePhoneNumber(valor)
// direto, sem DDI. Um default como "11999999999" (sem "+") nao parseia -- o
// campo aparece vazio na tela, mas values[key] continuaria com o default, e o
// agente submeteria o valor antigo sem perceber que o campo parecia vazio. So
// aceita o default de telefone quando ele de fato parseia como numero valido.
const normalizeDefaultValue = field => {
  const defaultValue = field.default_value ?? '';
  if (field.type !== 'phone' || !defaultValue) return defaultValue;

  try {
    const parsed = parsePhoneNumber(defaultValue);
    return parsed?.isValid() ? defaultValue : '';
  } catch (error) {
    return '';
  }
};

const open = (executedMacro, inputFields = []) => {
  macro.value = executedMacro;
  fields.value = inputFields;

  Object.keys(values).forEach(key => delete values[key]);
  inputFields.forEach(field => {
    values[field.key] = normalizeDefaultValue(field);
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
  // $touch() na raiz propaga para o filho -- e o que faz o erro interno do
  // PhoneNumberInput aparecer quando o agente mexeu no campo.
  v$.value.$touch();

  // NUNCA use v$.value.$invalid aqui. O PhoneNumberInput chama useVuelidate()
  // por conta propria, e o Vuelidate registra esse resultado no coletor do
  // ancestral mais proximo que tambem use useVuelidate -- este modal. O
  // estado interno dele (ex.: DDI que o componente deriva do fuso horario do
  // navegador, sem relacao com o valor do campo) entra flat no $invalid
  // agregado, mesmo para um campo de telefone opcional e nunca tocado pelo
  // agente. Sem este filtro, handleConfirm faria `return` em silencio: botao
  // vivo, clique sem efeito, nenhuma mensagem nossa -- o mesmo modo de falha
  // que o `close` pos-confirm ja tinha custado caro na fatia 3. Por isso o
  // portao olha campo a campo, so os que este modal declara.
  const hasInvalidField = fields.value.some(
    field => v$.value[field.key]?.$invalid
  );
  if (hasInvalidField) return;

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
        <!-- Telefone e um composto (botao de pais + input) sem um unico campo
             focavel com o id do label -- por isso ganha `id` em vez de `for`,
             e o grupo abaixo se liga a ele via aria-labelledby. -->
        <label
          :id="
            isPhoneField(field) ? `macro-input-${field.key}-label` : undefined
          "
          :for="isPhoneField(field) ? undefined : `macro-input-${field.key}`"
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
          v-else-if="
            controlFor(field) === 'cpf' || controlFor(field) === 'cnpj'
          "
          :id="`macro-input-${field.key}`"
          :model-value="values[field.key]"
          size="md"
          type="text"
          inputmode="numeric"
          autocomplete="off"
          :maxlength="maxLengthFor(field)"
          :required="field.required"
          :placeholder="field.placeholder"
          :message="errorFor(field.key)"
          :message-type="v$[field.key].$error ? 'error' : 'info'"
          @input="handleDocumentInput(field, $event)"
          @blur="v$[field.key].$touch"
        />

        <div
          v-else-if="isPhoneField(field)"
          role="group"
          :aria-labelledby="`macro-input-${field.key}-label`"
        >
          <!-- O componente so propaga o valor quando o numero e valido; um
               numero parcial mantem values[field.key] em ''. O botao
               Executar ja fica desabilitado enquanto isso (ver isComplete),
               e o erro de formato mostrado e o interno do componente -- nao
               empilhar uma segunda mensagem de erro nossa por cima. -->
          <PhoneNumberInput
            v-model="values[field.key]"
            :placeholder="field.placeholder"
          />
        </div>

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
