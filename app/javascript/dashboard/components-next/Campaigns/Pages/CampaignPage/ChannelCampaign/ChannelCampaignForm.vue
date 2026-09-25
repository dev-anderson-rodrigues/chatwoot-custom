<script setup>
import { reactive, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useMapGetter } from 'dashboard/composables/store';
import {
  CHANNEL_CAMPAIGN_KINDS,
  CHANNEL_CAMPAIGN_LABELS,
  getChannelTypesForKind,
} from 'dashboard/helper/channelCampaigns';

import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';

const props = defineProps({
  kind: {
    type: String,
    default: CHANNEL_CAMPAIGN_KINDS.EMAIL,
  },
});

// O formulário só emite `submit`; quem cria a campanha (e decide fechar) é o diálogo. Assim, se a API
// recusar, o texto da cobrança não se perde.
const emit = defineEmits(['submit', 'cancel']);

const { t } = useI18n();

const BASE_KEY = 'CAMPAIGN.CHANNEL_CAMPAIGN.CREATE.FORM';

// As chaves de Liquid ficam aqui (e nao no template) porque `}}` dentro de uma
// interpolacao do Vue fecha a expressao antes da hora.
const variableExamples = computed(() => {
  const key = t(`${BASE_KEY}.MESSAGE.ATTRIBUTE_KEY`);
  const defaultText = t(`${BASE_KEY}.MESSAGE.DEFAULT_TEXT`);
  return {
    name: '{{ contact.name }}',
    attribute: `{{ contact.custom_attribute.${key} }}`,
    key,
    fallback: `{{ contact.name | default: '${defaultText}' }}`,
  };
});

const formState = {
  uiFlags: useMapGetter('campaigns/getUIFlags'),
  labels: useMapGetter('labels/getLabels'),
  inboxes: useMapGetter('inboxes/getInboxes'),
};

const state = reactive({
  title: '',
  subject: '',
  message: '',
  inboxId: null,
  scheduledAt: null,
  selectedAudience: [],
});

const isEmail = computed(() => props.kind === CHANNEL_CAMPAIGN_KINDS.EMAIL);

// O agendador so pega campanha agendada nos ultimos dias, e data no passado significa "enviar agora": deixar
// digitar uma data antiga criaria uma campanha que nunca dispara ou dispara sem o operador esperar.
// Tolerancia de 1 minuto para o relogio do navegador.
const notInPast = value =>
  !value || new Date(value).getTime() >= Date.now() - 60000;

const rules = computed(() => ({
  title: { required, minLength: minLength(1) },
  subject: isEmail.value ? { required } : {},
  message: { required, minLength: minLength(1) },
  inboxId: { required },
  scheduledAt: { required, notInPast },
  selectedAudience: { required },
}));

const v$ = useVuelidate(rules, state);

const isCreating = computed(() => formState.uiFlags.value.isCreating);

const currentDateTime = computed(() => {
  // Added to disable the scheduled at field from being set to the current time
  const now = new Date();
  const localTime = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
  return localTime.toISOString().slice(0, 16);
});

const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;

const audienceList = computed(
  () =>
    formState.labels.value?.map(label => ({
      value: label.id,
      label: label.title,
    })) ?? []
);

const inboxOptions = computed(() => {
  const channelTypes = getChannelTypesForKind(props.kind);
  return (formState.inboxes.value ?? [])
    .filter(inbox => channelTypes.includes(inbox.channel_type))
    .map(inbox => ({
      value: inbox.id,
      // Nas outras caixas o nome do canal ajuda a distinguir (Telegram, Instagram...).
      label: isEmail.value
        ? inbox.name
        : `${inbox.name} · ${CHANNEL_CAMPAIGN_LABELS[inbox.channel_type] ?? ''}`,
    }));
});

const getErrorMessage = (field, errorKey) =>
  v$.value[field].$error ? t(`${BASE_KEY}.${errorKey}.ERROR`) : '';

const scheduledAtError = computed(() => {
  if (!v$.value.scheduledAt.$error) return '';

  const isPast = v$.value.scheduledAt.$errors.some(
    error => error.$validator === 'notInPast'
  );
  return t(`${BASE_KEY}.SCHEDULED_AT.${isPast ? 'PAST_ERROR' : 'ERROR'}`);
});

const formErrors = computed(() => ({
  title: getErrorMessage('title', 'TITLE'),
  subject: getErrorMessage('subject', 'SUBJECT'),
  message: getErrorMessage('message', 'MESSAGE'),
  inbox: getErrorMessage('inboxId', 'INBOX'),
  scheduledAt: scheduledAtError.value,
  audience: getErrorMessage('selectedAudience', 'AUDIENCE'),
}));

const isSubmitDisabled = computed(() => v$.value.$invalid);

const formatToUTCString = localDateTime =>
  localDateTime ? new Date(localDateTime).toISOString() : null;

const handleCancel = () => emit('cancel');

const prepareCampaignDetails = () => ({
  title: state.title,
  message: state.message,
  inbox_id: state.inboxId,
  scheduled_at: formatToUTCString(state.scheduledAt),
  audience: state.selectedAudience?.map(id => ({
    id,
    type: 'Label',
  })),
  // O assunto do e-mail viaja em template_params (o backend exige para caixa de e-mail).
  ...(isEmail.value ? { template_params: { subject: state.subject } } : {}),
});

const handleSubmit = async () => {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) return;

  emit('submit', prepareCampaignDetails());
};
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="handleSubmit">
    <Input
      v-model="state.title"
      :label="t(`${BASE_KEY}.TITLE.LABEL`)"
      :placeholder="t(`${BASE_KEY}.TITLE.PLACEHOLDER`)"
      :message="formErrors.title"
      :message-type="formErrors.title ? 'error' : 'info'"
    />

    <Input
      v-if="isEmail"
      v-model="state.subject"
      :label="t(`${BASE_KEY}.SUBJECT.LABEL`)"
      :placeholder="t(`${BASE_KEY}.SUBJECT.PLACEHOLDER`)"
      :message="formErrors.subject"
      :message-type="formErrors.subject ? 'error' : 'info'"
    />

    <div class="flex flex-col gap-1.5">
      <TextArea
        v-model="state.message"
        :label="t(`${BASE_KEY}.MESSAGE.LABEL`)"
        :placeholder="t(`${BASE_KEY}.MESSAGE.PLACEHOLDER`)"
        auto-height
        min-height="8rem"
        max-height="16rem"
        :message="formErrors.message"
        :message-type="formErrors.message ? 'error' : 'info'"
      />
      <p class="mb-0 text-xs text-n-slate-11">
        {{ t(`${BASE_KEY}.MESSAGE.HINT`, variableExamples) }}
      </p>
    </div>

    <div class="flex flex-col gap-1">
      <label for="inbox" class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ t(`${BASE_KEY}.INBOX.LABEL`) }}
      </label>
      <ComboBox
        id="inbox"
        v-model="state.inboxId"
        :options="inboxOptions"
        :has-error="!!formErrors.inbox"
        :placeholder="t(`${BASE_KEY}.INBOX.PLACEHOLDER`)"
        :message="formErrors.inbox"
        class="[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
      />
      <p v-if="!inboxOptions.length" class="mb-0 text-xs text-n-slate-11">
        {{ t(`${BASE_KEY}.INBOX.EMPTY`) }}
      </p>
      <p
        v-if="!isEmail"
        class="px-3 py-2 mt-1 mb-0 text-xs rounded-lg bg-n-amber-3 text-n-amber-11"
      >
        {{ t(`${BASE_KEY}.CHANNELS_NOTICE`) }}
      </p>
    </div>

    <div class="flex flex-col gap-1">
      <label for="audience" class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ t(`${BASE_KEY}.AUDIENCE.LABEL`) }}
      </label>
      <TagMultiSelectComboBox
        v-model="state.selectedAudience"
        :options="audienceList"
        :label="t(`${BASE_KEY}.AUDIENCE.LABEL`)"
        :placeholder="t(`${BASE_KEY}.AUDIENCE.PLACEHOLDER`)"
        :has-error="!!formErrors.audience"
        :message="formErrors.audience"
        class="[&>div>button]:bg-n-alpha-black2"
      />
    </div>

    <Input
      v-model="state.scheduledAt"
      :label="t(`${BASE_KEY}.SCHEDULED_AT.LABEL`)"
      type="datetime-local"
      :min="currentDateTime"
      :placeholder="t(`${BASE_KEY}.SCHEDULED_AT.PLACEHOLDER`)"
      :message="
        formErrors.scheduledAt ||
        t(`${BASE_KEY}.SCHEDULED_AT.HINT`, { timezone })
      "
      :message-type="formErrors.scheduledAt ? 'error' : 'info'"
    />

    <div class="flex items-center justify-between w-full gap-3">
      <Button
        variant="faded"
        color="slate"
        type="button"
        :label="t(`${BASE_KEY}.BUTTONS.CANCEL`)"
        class="w-full bg-n-alpha-2 text-n-blue-11 hover:bg-n-alpha-3"
        @click="handleCancel"
      />
      <Button
        :label="t(`${BASE_KEY}.BUTTONS.CREATE`)"
        class="w-full"
        type="submit"
        :is-loading="isCreating"
        :disabled="isCreating || isSubmitDisabled"
      />
    </div>
  </form>
</template>
