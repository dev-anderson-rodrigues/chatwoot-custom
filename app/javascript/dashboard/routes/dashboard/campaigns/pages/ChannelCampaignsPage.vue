<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useToggle } from '@vueuse/core';
import { useStoreGetters, useMapGetter } from 'dashboard/composables/store';
import { CAMPAIGN_TYPES } from 'shared/constants/campaign';
import {
  CHANNEL_CAMPAIGN_KINDS,
  getChannelTypesForKind,
  getCampaignAnalyticsRouteName,
} from 'dashboard/helper/channelCampaigns';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CampaignLayout from 'dashboard/components-next/Campaigns/CampaignLayout.vue';
import CampaignList from 'dashboard/components-next/Campaigns/Pages/CampaignPage/CampaignList.vue';
import ChannelCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/ChannelCampaign/ChannelCampaignDialog.vue';
import ConfirmDeleteCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/ConfirmDeleteCampaignDialog.vue';
import SMSCampaignEmptyState from 'dashboard/components-next/Campaigns/EmptyState/SMSCampaignEmptyState.vue';

// Uma pagina para as duas abas (E-mail e Outros canais): quem diz qual e e o `meta.kind`
// da rota. O que muda entre elas e so a lista de caixas, o assunto do e-mail e os textos.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const getters = useStoreGetters();

const kind = computed(() => route.meta.kind || CHANNEL_CAMPAIGN_KINDS.EMAIL);
const scope = computed(() =>
  kind.value === CHANNEL_CAMPAIGN_KINDS.EMAIL
    ? 'CAMPAIGN.EMAIL'
    : 'CAMPAIGN.CHANNELS'
);

const selectedCampaign = ref(null);
const [showCampaignDialog, toggleCampaignDialog] = useToggle();

// A pagina fica em cache (keep-alive) e e a mesma para as duas abas: trocar de aba nao pode
// deixar aberto o formulario da outra.
watch(kind, () => toggleCampaignDialog(false));

const uiFlags = useMapGetter('campaigns/getUIFlags');
const isFetchingCampaigns = computed(() => uiFlags.value.isFetching);

const confirmDeleteCampaignDialogRef = ref(null);

const campaigns = computed(() =>
  getters['campaigns/getCampaigns'].value(
    CAMPAIGN_TYPES.ONE_OFF,
    getChannelTypesForKind(kind.value)
  )
);

const hasNoCampaigns = computed(
  () => campaigns.value?.length === 0 && !isFetchingCampaigns.value
);

const handleDelete = campaign => {
  selectedCampaign.value = campaign;
  confirmDeleteCampaignDialogRef.value.dialogRef.open();
};

const handleAnalytics = campaign => {
  router.push({
    name: getCampaignAnalyticsRouteName(campaign.inbox?.channel_type),
    params: { campaignId: campaign.id },
  });
};
</script>

<template>
  <CampaignLayout
    :header-title="t(`${scope}.HEADER_TITLE`)"
    :button-label="t(`${scope}.NEW_CAMPAIGN`)"
    @click="toggleCampaignDialog()"
    @close="toggleCampaignDialog(false)"
  >
    <template #action>
      <ChannelCampaignDialog
        v-if="showCampaignDialog"
        :kind="kind"
        @close="toggleCampaignDialog(false)"
      />
    </template>
    <div
      v-if="isFetchingCampaigns"
      class="flex items-center justify-center py-10 text-n-slate-11"
    >
      <Spinner />
    </div>
    <CampaignList
      v-else-if="!hasNoCampaigns"
      :campaigns="campaigns"
      @delete="handleDelete"
      @analytics="handleAnalytics"
    />
    <SMSCampaignEmptyState
      v-else
      :title="t(`${scope}.EMPTY_STATE.TITLE`)"
      :subtitle="t(`${scope}.EMPTY_STATE.SUBTITLE`)"
      class="pt-14"
    />
    <ConfirmDeleteCampaignDialog
      ref="confirmDeleteCampaignDialogRef"
      :selected-campaign="selectedCampaign"
    />
  </CampaignLayout>
</template>
