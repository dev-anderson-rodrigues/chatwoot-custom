<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert, useTrack } from 'dashboard/composables';
import { CAMPAIGN_TYPES } from 'shared/constants/campaign.js';
import { CAMPAIGNS_EVENTS } from 'dashboard/helper/AnalyticsHelper/events.js';
import { CHANNEL_CAMPAIGN_KINDS } from 'dashboard/helper/channelCampaigns';

import ChannelCampaignForm from 'dashboard/components-next/Campaigns/Pages/CampaignPage/ChannelCampaign/ChannelCampaignForm.vue';

const props = defineProps({
  kind: {
    type: String,
    default: CHANNEL_CAMPAIGN_KINDS.EMAIL,
  },
});

const emit = defineEmits(['close']);

const store = useStore();
const { t } = useI18n();

const BASE_KEY = 'CAMPAIGN.CHANNEL_CAMPAIGN.CREATE';

const dialogTitle = computed(() =>
  props.kind === CHANNEL_CAMPAIGN_KINDS.EMAIL
    ? t(`${BASE_KEY}.TITLE_EMAIL`)
    : t(`${BASE_KEY}.TITLE_CHANNELS`)
);

// Só fecha quando a campanha foi criada. Se a API recusar, o formulário continua aberto com o texto que o
// operador escreveu (a mensagem de cobrança é longa e cheia de variáveis) e o alerta traz o motivo dado pelo
// backend (ex.: caixa de e-mail sem SMTP próprio).
const addCampaign = async campaignDetails => {
  try {
    await store.dispatch('campaigns/create', campaignDetails);

    // tracking this here instead of the store to track the type of campaign
    useTrack(CAMPAIGNS_EVENTS.CREATE_CAMPAIGN, {
      type: CAMPAIGN_TYPES.ONE_OFF,
    });

    useAlert(t(`${BASE_KEY}.FORM.API.SUCCESS_MESSAGE`));
    emit('close');
  } catch (error) {
    const errorMessage =
      error?.response?.data?.message || t(`${BASE_KEY}.FORM.API.ERROR_MESSAGE`);
    useAlert(errorMessage);
  }
};

const handleClose = () => emit('close');
</script>

<template>
  <div
    class="w-[25rem] z-50 min-w-0 absolute top-10 ltr:right-0 rtl:left-0 bg-n-alpha-3 backdrop-blur-[100px] p-6 rounded-xl border border-n-weak shadow-md flex flex-col gap-6"
  >
    <h3 class="text-base font-medium text-n-slate-12">
      {{ dialogTitle }}
    </h3>
    <ChannelCampaignForm
      :kind="kind"
      @submit="addCampaign"
      @cancel="handleClose"
    />
  </div>
</template>
