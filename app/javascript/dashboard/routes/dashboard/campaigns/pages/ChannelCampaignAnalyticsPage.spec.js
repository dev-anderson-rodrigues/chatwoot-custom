import { ref } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import CampaignsAPI from 'dashboard/api/campaigns';
import CampaignMetricCard from 'dashboard/components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignMetricCard.vue';
import CampaignDeliveryTable from 'dashboard/components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignDeliveryTable.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import ChannelCampaignAnalyticsPage from './ChannelCampaignAnalyticsPage.vue';

const SCOPE = 'CAMPAIGN.CHANNEL_CAMPAIGN.ANALYTICS';
const push = vi.fn();
const route = { params: { campaignId: '2' }, meta: { kind: 'email' } };

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => route,
  useRouter: () => ({ push }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () =>
    ref([
      {
        id: 2,
        title: 'Cobrança de setembro',
        campaign_status: 'completed',
        scheduled_at: 1790219000,
        inbox: { name: 'Cobrança', channel_type: 'Channel::Email' },
      },
    ]),
  useStore: () => ({ dispatch: vi.fn() }),
}));

vi.mock('dashboard/api/campaigns', () => ({
  default: { analyticsMetrics: vi.fn(), analyticsContacts: vi.fn() },
}));

vi.mock('shared/helpers/timeHelper', () => ({ messageStamp: () => 'agora' }));

// Layout que renderiza o slot e expoe o evento de navegacao do breadcrumb.
const LayoutStub = {
  name: 'LayoutStub',
  props: ['breadcrumbItems'],
  emits: ['breadcrumbClick'],
  template: '<div><slot /></div>',
};

// A tabela real so aparece com dados; o stub deixa o slot dos filtros (onde ficam as abas).
const TableWithFiltersStub = {
  name: 'TableWithFiltersStub',
  props: ['i18nScope'],
  template: '<div><slot name="filters" /></div>',
};

const metrics = (overrides = {}) => ({
  audience: 5,
  sent: 2,
  delivered: 0,
  read: 0,
  failed: 0,
  skipped: 3,
  status_counts: {
    queued: 0,
    sent: 2,
    delivered: 0,
    read: 0,
    failed: 0,
    skipped: 3,
  },
  ...overrides,
});

const mountPage = async (metricsResponse, kind = 'email') => {
  route.meta.kind = kind;
  CampaignsAPI.analyticsMetrics.mockResolvedValue({ data: metricsResponse });
  CampaignsAPI.analyticsContacts.mockResolvedValue({
    data: { payload: [], meta: { total_count: 0 } },
  });

  const wrapper = shallowMount(ChannelCampaignAnalyticsPage, {
    global: {
      stubs: {
        CampaignAnalyticsLayout: LayoutStub,
        CampaignDeliveryTable: TableWithFiltersStub,
      },
    },
  });
  await flushPromises();
  return wrapper;
};

const metricKeys = wrapper =>
  wrapper
    .findAllComponents(CampaignMetricCard)
    .map(card =>
      card.props('label').replace(`${SCOPE}.METRICS.`, '').replace('.LABEL', '')
    );

const tabs = wrapper => wrapper.findComponent(TabBar).props('tabs');

const withReceipts = () =>
  metrics({
    delivered: 3,
    read: 1,
    status_counts: { sent: 0, delivered: 2, read: 1, failed: 0, skipped: 2 },
  });

describe('ChannelCampaignAnalyticsPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('num canal sem recibo de entrega (e-mail)', () => {
    it('mostra publico, enviadas, falharam e puladas, sem entregues/lidas (seriam sempre 0)', async () => {
      const wrapper = await mountPage(metrics());

      expect(metricKeys(wrapper)).toEqual([
        'AUDIENCE',
        'SENT',
        'FAILED',
        'SKIPPED',
      ]);
    });

    it('as abas nao trazem entregue nem lida', async () => {
      const wrapper = await mountPage(metrics());

      expect(tabs(wrapper).map(tab => tab.key)).toEqual([
        'all',
        'sent',
        'failed',
        'skipped',
      ]);
    });

    it('cada aba mostra a contagem exata do backend (todas = publico)', async () => {
      const wrapper = await mountPage(metrics());

      const counts = Object.fromEntries(
        tabs(wrapper).map(tab => [tab.key, tab.count])
      );
      expect(counts).toEqual({ all: 5, sent: 2, failed: 0, skipped: 3 });
    });
  });

  describe('num canal que informa entrega (Instagram, Facebook...)', () => {
    it('passa a mostrar entregues e lidas', async () => {
      const wrapper = await mountPage(withReceipts());

      expect(metricKeys(wrapper)).toEqual([
        'AUDIENCE',
        'SENT',
        'DELIVERED',
        'READ',
        'FAILED',
        'SKIPPED',
      ]);
    });

    it('e as abas acompanham', async () => {
      const wrapper = await mountPage(withReceipts());

      expect(tabs(wrapper).map(tab => tab.key)).toEqual([
        'all',
        'sent',
        'delivered',
        'read',
        'failed',
        'skipped',
      ]);
    });
  });

  it('a tabela usa o escopo de textos proprio (enviada e "Enviada", nao "aguardando entrega")', async () => {
    const wrapper = await mountPage(metrics());

    expect(wrapper.findComponent(TableWithFiltersStub).props('i18nScope')).toBe(
      SCOPE
    );
    // A tabela real herda o escopo do WhatsApp por padrao: a tela nova precisa passar o dela.
    expect(CampaignDeliveryTable.props.i18nScope.default).toBe(
      'CAMPAIGN.WHATSAPP.ANALYTICS'
    );
  });

  describe('breadcrumb', () => {
    it('volta para a aba E-mail', async () => {
      const wrapper = await mountPage(metrics(), 'email');

      wrapper.findComponent(LayoutStub).vm.$emit('breadcrumbClick');

      expect(push).toHaveBeenCalledWith({ name: 'campaigns_email_index' });
    });

    it('volta para a aba Outros canais', async () => {
      const wrapper = await mountPage(metrics(), 'channels');

      wrapper.findComponent(LayoutStub).vm.$emit('breadcrumbClick');

      expect(push).toHaveBeenCalledWith({ name: 'campaigns_channels_index' });
    });

    it('o caminho diz de que aba a campanha e', async () => {
      const email = await mountPage(metrics(), 'email');
      const channels = await mountPage(metrics(), 'channels');

      const labels = wrapper =>
        wrapper
          .findComponent(LayoutStub)
          .props('breadcrumbItems')
          .map(item => item.label);
      expect(labels(email)).toEqual([
        `${SCOPE}.BREADCRUMB.CAMPAIGNS`,
        `${SCOPE}.BREADCRUMB.EMAIL`,
        'Cobrança de setembro',
      ]);
      expect(labels(channels)).toEqual([
        `${SCOPE}.BREADCRUMB.CAMPAIGNS`,
        `${SCOPE}.BREADCRUMB.CHANNELS`,
        'Cobrança de setembro',
      ]);
    });
  });

  it('sem dados (publico 0) mostra o estado vazio, nao a tabela nem as metricas', async () => {
    const wrapper = await mountPage(
      metrics({ audience: 0, sent: 0, skipped: 0, status_counts: {} })
    );

    expect(wrapper.findAllComponents(CampaignMetricCard)).toHaveLength(0);
    expect(wrapper.findComponent(TableWithFiltersStub).exists()).toBe(false);
    expect(wrapper.text()).toContain(`${SCOPE}.EMPTY_STATE`);
  });

  describe('falha ao atualizar', () => {
    it('numa leitura de polling, uma falha transitoria nao derruba a tela: ficam os dados da ultima leitura', async () => {
      const wrapper = await mountPage(metrics());
      CampaignsAPI.analyticsMetrics.mockRejectedValue(new Error('timeout'));
      CampaignsAPI.analyticsContacts.mockRejectedValue(new Error('timeout'));

      await wrapper.vm.fetchMetrics({ showLoading: false });
      await wrapper.vm.fetchDeliveries({ showLoading: false });
      await flushPromises();

      expect(metricKeys(wrapper)).toEqual([
        'AUDIENCE',
        'SENT',
        'FAILED',
        'SKIPPED',
      ]);
      expect(wrapper.text()).not.toContain(`${SCOPE}.EMPTY_STATE.ERROR`);
    });

    it('na primeira leitura, a falha mostra o estado de erro', async () => {
      CampaignsAPI.analyticsMetrics.mockRejectedValue(new Error('boom'));
      CampaignsAPI.analyticsContacts.mockRejectedValue(new Error('boom'));

      const wrapper = shallowMount(ChannelCampaignAnalyticsPage, {
        global: {
          stubs: {
            CampaignAnalyticsLayout: LayoutStub,
            CampaignDeliveryTable: TableWithFiltersStub,
          },
        },
      });
      await flushPromises();

      expect(wrapper.findAllComponents(CampaignMetricCard)).toHaveLength(0);
      expect(wrapper.text()).toContain(`${SCOPE}.EMPTY_STATE.ERROR.TITLE`);
    });
  });
});
