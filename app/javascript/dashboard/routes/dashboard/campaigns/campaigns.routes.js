import { frontendURL } from 'dashboard/helper/URLHelper.js';

import CampaignsPageRouteView from './pages/CampaignsPageRouteView.vue';
import LiveChatCampaignsPage from './pages/LiveChatCampaignsPage.vue';
import SMSCampaignsPage from './pages/SMSCampaignsPage.vue';
import WhatsAppCampaignsPage from './pages/WhatsAppCampaignsPage.vue';
import WhatsAppCampaignAnalyticsPage from './pages/WhatsAppCampaignAnalyticsPage.vue';
import ChannelCampaignsPage from './pages/ChannelCampaignsPage.vue';
import ChannelCampaignAnalyticsPage from './pages/ChannelCampaignAnalyticsPage.vue';
import { CHANNEL_CAMPAIGN_KINDS } from 'dashboard/helper/channelCampaigns';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const meta = {
  featureFlag: FEATURE_FLAGS.CAMPAIGNS,
  permissions: ['administrator'],
};

const campaignsRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/campaigns'),
      component: CampaignsPageRouteView,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'campaigns_ongoing_index', params: to.params };
          },
        },
        {
          path: 'ongoing',
          name: 'campaigns_ongoing_index',
          meta,
          redirect: to => {
            return { name: 'campaigns_livechat_index', params: to.params };
          },
        },
        {
          path: 'one_off',
          name: 'campaigns_one_off_index',
          meta,
          redirect: to => {
            return { name: 'campaigns_sms_index', params: to.params };
          },
        },
        {
          path: 'live_chat',
          name: 'campaigns_livechat_index',
          meta,
          component: LiveChatCampaignsPage,
        },
        {
          path: 'sms',
          name: 'campaigns_sms_index',
          meta,
          component: SMSCampaignsPage,
        },
        {
          path: 'whatsapp',
          name: 'campaigns_whatsapp_index',
          meta: {
            ...meta,
            featureFlag: FEATURE_FLAGS.WHATSAPP_CAMPAIGNS,
          },
          component: WhatsAppCampaignsPage,
        },
        {
          path: 'whatsapp/:campaignId/analytics',
          name: 'campaigns_whatsapp_analytics',
          meta: {
            ...meta,
            featureFlag: FEATURE_FLAGS.WHATSAPP_CAMPAIGNS,
          },
          component: WhatsAppCampaignAnalyticsPage,
        },
        // [FORK] Disparo em massa por e-mail e por outras caixas (Onda 7 / fatia 2).
        // A mesma pagina atende as duas abas; quem diz qual e e o `meta.kind`.
        {
          path: 'email',
          name: 'campaigns_email_index',
          meta: { ...meta, kind: CHANNEL_CAMPAIGN_KINDS.EMAIL },
          component: ChannelCampaignsPage,
        },
        {
          path: 'email/:campaignId/analytics',
          name: 'campaigns_email_analytics',
          meta: { ...meta, kind: CHANNEL_CAMPAIGN_KINDS.EMAIL },
          component: ChannelCampaignAnalyticsPage,
        },
        {
          path: 'channels',
          name: 'campaigns_channels_index',
          meta: { ...meta, kind: CHANNEL_CAMPAIGN_KINDS.CHANNELS },
          component: ChannelCampaignsPage,
        },
        {
          path: 'channels/:campaignId/analytics',
          name: 'campaigns_channels_analytics',
          meta: { ...meta, kind: CHANNEL_CAMPAIGN_KINDS.CHANNELS },
          component: ChannelCampaignAnalyticsPage,
        },
      ],
    },
  ],
};

export default campaignsRoutes;
