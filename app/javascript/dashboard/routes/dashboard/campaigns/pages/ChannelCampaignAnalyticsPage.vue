<script setup>
import {
  computed,
  onActivated,
  onBeforeUnmount,
  onDeactivated,
  reactive,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { getInboxIconByType } from 'dashboard/helper/inbox';
import { CHANNEL_CAMPAIGN_KINDS } from 'dashboard/helper/channelCampaigns';
import { messageStamp } from 'shared/helpers/timeHelper';
import CampaignsAPI from 'dashboard/api/campaigns';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import CampaignAnalyticsLayout from 'dashboard/components-next/Campaigns/CampaignAnalyticsLayout.vue';
import CampaignMetricCard from 'dashboard/components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignMetricCard.vue';
import CampaignDeliveryTable from 'dashboard/components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignDeliveryTable.vue';

// [FORK] Analytics das campanhas por e-mail e outras caixas (Onda 7 / fatia 2).
//
// Parte da tela do WhatsApp, com as diferencas que vem do canal: aqui `sent` e final (e-mail
// e Telegram nao tem recibo), entao "entregue/lido" so aparecem quando o canal informa
// (Instagram, Facebook...), e nao ha o grafico de entrega. O que mais importa nesta tela e a
// tabela: quem foi pulado ou falhou, e por que.
const SCOPE = 'CAMPAIGN.CHANNEL_CAMPAIGN.ANALYTICS';
const DELIVERIES_PER_PAGE = 25;
const ANALYTICS_POLL_INTERVAL = 5000;
const CAMPAIGN_STATUS_PROCESSING = 'processing';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();

const state = reactive({
  metrics: null,
  deliveries: [],
  meta: {},
  status: 'all',
  page: 1,
  isFetchingMetrics: true,
  isFetchingDeliveries: true,
  metricsError: false,
  deliveriesError: false,
});

let metricsRequestId = 0;
let deliveriesRequestId = 0;
let pollingTimeoutId;
let isPageActive = false;
let skipNextFilterRefresh = false;

const campaigns = useMapGetter('campaigns/getAllCampaigns');

const kind = computed(() => route.meta.kind || CHANNEL_CAMPAIGN_KINDS.EMAIL);
const campaignId = computed(() => Number(route.params.campaignId));
const campaign = computed(() =>
  campaigns.value.find(record => Number(record.id) === campaignId.value)
);
const campaignTitle = computed(
  () => campaign.value?.title || `#${campaignId.value}`
);
const isCampaignProcessing = computed(
  () => campaign.value?.campaign_status === CAMPAIGN_STATUS_PROCESSING
);
// "Agendada para" so enquanto a campanha nao comecou; depois e a data do envio.
const dateLabelKey = computed(() =>
  campaign.value?.campaign_status === 'active' ? 'SCHEDULED_FOR' : 'SENT_ON'
);

const inboxIcon = computed(() => {
  const inbox = campaign.value?.inbox;
  if (!inbox) return '';

  return getInboxIconByType(
    inbox.channel_type,
    inbox.medium,
    'fill',
    inbox.voice_enabled
  );
});

const breadcrumbItems = computed(() => [
  { label: t(`${SCOPE}.BREADCRUMB.CAMPAIGNS`) },
  {
    label: t(
      kind.value === CHANNEL_CAMPAIGN_KINDS.EMAIL
        ? `${SCOPE}.BREADCRUMB.EMAIL`
        : `${SCOPE}.BREADCRUMB.CHANNELS`
    ),
  },
  { label: campaignTitle.value },
]);

const metricCount = key => Number(state.metrics?.[key] || 0);
const audience = computed(() => metricCount('audience'));
const queuedCount = computed(() =>
  Number(state.metrics?.status_counts?.queued || 0)
);

const processingBanner = computed(() => {
  if (!state.metrics || !audience.value) {
    return t(`${SCOPE}.PROCESSING_BANNER.DEFAULT`);
  }

  if (queuedCount.value) {
    return t(
      `${SCOPE}.PROCESSING_BANNER.QUEUED`,
      { count: queuedCount.value },
      queuedCount.value
    );
  }

  return t(`${SCOPE}.PROCESSING_BANNER.COMPLETING`);
});

const analyticsEmptyState = computed(() => {
  if (state.isFetchingMetrics || audience.value > 0) return null;

  if (state.metricsError) {
    return {
      icon: 'i-lucide-triangle-alert',
      title: t(`${SCOPE}.EMPTY_STATE.ERROR.TITLE`),
      description: t(`${SCOPE}.EMPTY_STATE.ERROR.DESCRIPTION`),
    };
  }

  if (isCampaignProcessing.value) {
    return {
      icon: 'i-lucide-clock-3',
      title: t(`${SCOPE}.EMPTY_STATE.PENDING.TITLE`),
      description: t(`${SCOPE}.EMPTY_STATE.PENDING.DESCRIPTION`),
    };
  }

  return {
    icon: 'i-lucide-chart-no-axes-column',
    title: t(`${SCOPE}.EMPTY_STATE.UNAVAILABLE.TITLE`),
    description: t(`${SCOPE}.EMPTY_STATE.UNAVAILABLE.DESCRIPTION`),
  };
});

const showAnalytics = computed(
  () => !state.isFetchingMetrics && !analyticsEmptyState.value
);

const metricRate = key => {
  if (!audience.value) return '';

  return t(`${SCOPE}.RATE`, {
    value: Math.round((metricCount(key) / audience.value) * 100),
  });
};

// "Entregue" e "lido" so aparecem quando o canal informa (contagem > 0): num canal sem recibo
// eles seriam sempre 0 e passariam a impressao de que nada chegou.
const reportsDelivery = computed(
  () => metricCount('delivered') > 0 || metricCount('read') > 0
);

const metricKeys = computed(() => [
  'audience',
  'sent',
  ...(reportsDelivery.value ? ['delivered', 'read'] : []),
  'failed',
  'skipped',
]);

const metrics = computed(() =>
  metricKeys.value.map(key => {
    const scope = `${SCOPE}.METRICS.${key.toUpperCase()}`;

    return {
      key,
      label: t(`${scope}.LABEL`),
      hint: t(`${scope}.HINT`),
      value: metricCount(key),
      rate: key === 'audience' ? '' : metricRate(key),
    };
  })
);

const statusFilters = computed(() => [
  'all',
  'sent',
  ...(reportsDelivery.value ? ['delivered', 'read'] : []),
  'failed',
  'skipped',
]);

const statusTabs = computed(() =>
  statusFilters.value.map(key => ({
    key,
    label: t(
      key === 'all'
        ? `${SCOPE}.FILTERS.ALL`
        : `${SCOPE}.STATUS.${key.toUpperCase()}`
    ),
    count:
      key === 'all'
        ? audience.value
        : Number(state.metrics?.status_counts?.[key] || 0),
  }))
);

const activeTabIndex = computed(() =>
  Math.max(statusFilters.value.indexOf(state.status), 0)
);

const totalDeliveries = computed(() => Number(state.meta.total_count || 0));

const noDataMessage = computed(() => {
  if (state.deliveriesError) return t(`${SCOPE}.DELIVERIES_ERROR`);

  if (state.status === 'all') return t(`${SCOPE}.EMPTY`);

  return t(`${SCOPE}.EMPTY_FILTER`, {
    status: t(`${SCOPE}.STATUS.${state.status.toUpperCase()}`).toLowerCase(),
  });
});

const fetchMetrics = async ({
  id = campaignId.value,
  showLoading = true,
} = {}) => {
  metricsRequestId += 1;
  const requestId = metricsRequestId;
  if (showLoading) state.isFetchingMetrics = true;

  try {
    const { data } = await CampaignsAPI.analyticsMetrics(id);
    if (requestId !== metricsRequestId || id !== campaignId.value) return;

    state.metrics = data;
    state.metricsError = false;
  } catch {
    if (requestId !== metricsRequestId || id !== campaignId.value) return;

    // Numa leitura de polling, uma falha transitoria nao pode derrubar a tela: fica o que ja estava.
    if (!showLoading && state.metrics) return;

    state.metrics = null;
    state.metricsError = true;
  } finally {
    if (requestId === metricsRequestId && id === campaignId.value) {
      state.isFetchingMetrics = false;
    }
  }
};

const fetchDeliveries = async ({
  id = campaignId.value,
  status = state.status,
  page = state.page,
  showLoading = true,
} = {}) => {
  deliveriesRequestId += 1;
  const requestId = deliveriesRequestId;
  if (showLoading) state.isFetchingDeliveries = true;

  try {
    const { data } = await CampaignsAPI.analyticsContacts(id, {
      status: status === 'all' ? undefined : status,
      page,
    });
    if (requestId !== deliveriesRequestId || id !== campaignId.value) return;

    state.deliveries = data.payload;
    state.meta = data.meta;
    state.deliveriesError = false;
  } catch {
    if (requestId !== deliveriesRequestId || id !== campaignId.value) return;

    if (!showLoading) return;

    state.deliveries = [];
    state.meta = {};
    state.deliveriesError = true;
  } finally {
    if (requestId === deliveriesRequestId && id === campaignId.value) {
      state.isFetchingDeliveries = false;
    }
  }
};

const stopPolling = () => {
  window.clearTimeout(pollingTimeoutId);
  pollingTimeoutId = undefined;
};

const schedulePolling = () => {
  stopPolling();
  if (!isPageActive || !isCampaignProcessing.value) return;

  pollingTimeoutId = window.setTimeout(async () => {
    await Promise.all([
      fetchMetrics({ showLoading: false }),
      fetchDeliveries({ showLoading: false }),
      store.dispatch('campaigns/get'),
    ]);
    schedulePolling();
  }, ANALYTICS_POLL_INTERVAL);
};

const handleTabChange = tab => {
  if (tab.key === state.status) return;

  state.status = tab.key;
  state.page = 1;
};

const handlePageChange = page => {
  state.page = page;
};

const goToCampaigns = () => {
  router.push({
    name:
      kind.value === CHANNEL_CAMPAIGN_KINDS.EMAIL
        ? 'campaigns_email_index'
        : 'campaigns_channels_index',
  });
};

// The page is kept alive by the campaigns route view, so the campaign id is the
// trigger for a full refresh rather than the mount hook.
watch(
  campaignId,
  id => {
    if (!Number.isFinite(id)) return;

    metricsRequestId += 1;
    deliveriesRequestId += 1;
    state.metrics = null;
    state.deliveries = [];
    state.meta = {};
    state.metricsError = false;
    state.deliveriesError = false;
    state.isFetchingMetrics = true;
    state.isFetchingDeliveries = true;

    skipNextFilterRefresh = state.status !== 'all' || state.page !== 1;
    state.status = 'all';
    state.page = 1;
    fetchMetrics({ id });
    fetchDeliveries({ id, status: 'all', page: 1 });
    schedulePolling();
  },
  { immediate: true }
);

watch(
  () => [state.status, state.page],
  () => {
    if (skipNextFilterRefresh) {
      skipNextFilterRefresh = false;
      return;
    }

    fetchDeliveries();
  }
);

watch(isCampaignProcessing, schedulePolling);

onActivated(() => {
  isPageActive = true;
  schedulePolling();
});

onDeactivated(() => {
  isPageActive = false;
  stopPolling();
});

onBeforeUnmount(stopPolling);
</script>

<template>
  <CampaignAnalyticsLayout
    :breadcrumb-items="breadcrumbItems"
    @breadcrumb-click="goToCampaigns"
  >
    <div class="flex flex-col gap-6 pb-8">
      <Banner v-if="isCampaignProcessing" color="amber">
        <div class="flex items-start gap-3 text-start">
          <Icon
            icon="i-lucide-loader-circle"
            class="flex-shrink-0 mt-0.5 size-4 animate-spin"
          />
          <span>
            {{ processingBanner }}
          </span>
        </div>
      </Banner>

      <div
        v-if="campaign?.inbox"
        class="flex flex-wrap items-center text-sm gap-x-3 gap-y-2 text-n-slate-11"
      >
        <div class="flex items-center gap-1.5 min-w-0">
          <Icon :icon="inboxIcon" class="shrink-0 size-3.5 text-n-slate-12" />
          <span class="font-medium truncate text-n-slate-12">
            {{ campaign.inbox.name }}
          </span>
        </div>
        <span class="w-px h-3 rounded bg-n-strong" />
        <span class="whitespace-nowrap">
          {{
            t(`${SCOPE}.${dateLabelKey}`, {
              date: messageStamp(campaign.scheduled_at, 'LLL d, h:mm a'),
            })
          }}
        </span>
      </div>

      <div
        v-if="state.isFetchingMetrics"
        class="flex min-h-64 items-center justify-center rounded-xl border border-n-weak bg-n-solid-2 px-6 py-12"
        role="status"
        aria-live="polite"
      >
        <Icon
          icon="i-lucide-loader-circle"
          class="size-5 animate-spin text-n-slate-11"
        />
        <span class="sr-only">
          {{ t(`${SCOPE}.LOADING`) }}
        </span>
      </div>

      <div
        v-else-if="analyticsEmptyState"
        class="flex min-h-64 items-center justify-center rounded-xl border border-n-weak bg-n-solid-2 px-6 py-12 text-center"
      >
        <div class="flex max-w-md flex-col items-center gap-3">
          <div
            class="grid size-10 place-content-center rounded-full bg-n-alpha-2 text-n-slate-11"
          >
            <Icon :icon="analyticsEmptyState.icon" class="size-5" />
          </div>
          <div class="flex flex-col gap-1">
            <h3 class="text-base font-medium text-n-slate-12">
              {{ analyticsEmptyState.title }}
            </h3>
            <p class="text-sm text-n-slate-11">
              {{ analyticsEmptyState.description }}
            </p>
          </div>
        </div>
      </div>

      <div
        v-else
        class="grid grid-cols-1 gap-px overflow-hidden border rounded-xl sm:grid-cols-2 lg:grid-cols-3 bg-n-weak border-n-weak"
      >
        <CampaignMetricCard
          v-for="metric in metrics"
          :key="metric.key"
          :label="metric.label"
          :hint="metric.hint"
          :value="metric.value"
          :rate="metric.rate"
          :loading="state.isFetchingMetrics"
        />
      </div>

      <CampaignDeliveryTable
        v-if="showAnalytics"
        :deliveries="state.deliveries"
        :loading="state.isFetchingDeliveries"
        :no-data-message="noDataMessage"
        :i18n-scope="SCOPE"
      >
        <template #filters>
          <TabBar
            :tabs="statusTabs"
            :initial-active-tab="activeTabIndex"
            @tab-changed="handleTabChange"
          />
        </template>
        <template v-if="totalDeliveries > DELIVERIES_PER_PAGE" #footer>
          <PaginationFooter
            :current-page="state.page"
            :total-items="totalDeliveries"
            :items-per-page="DELIVERIES_PER_PAGE"
            :current-page-info="`${SCOPE}.PAGE_INFO`"
            class="!bg-transparent !px-5 rounded-b-xl before:hidden"
            @update:current-page="handlePageChange"
          />
        </template>
      </CampaignDeliveryTable>
    </div>
  </CampaignAnalyticsLayout>
</template>
