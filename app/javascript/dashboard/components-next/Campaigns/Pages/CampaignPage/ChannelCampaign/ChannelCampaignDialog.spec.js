import { flushPromises, shallowMount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import ChannelCampaignForm from './ChannelCampaignForm.vue';
import ChannelCampaignDialog from './ChannelCampaignDialog.vue';

const dispatch = vi.fn();
const useAlert = vi.fn();
const useTrack = vi.fn();

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => useAlert(...args),
  useTrack: (...args) => useTrack(...args),
}));

const details = { title: 'Cobrança', message: 'Olá', inbox_id: 1 };

const submitForm = async wrapper => {
  wrapper.findComponent(ChannelCampaignForm).vm.$emit('submit', details);
  await flushPromises();
};

describe('ChannelCampaignDialog', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('cria a campanha pela store e fecha quando deu certo', async () => {
    dispatch.mockResolvedValue();
    const wrapper = shallowMount(ChannelCampaignDialog, { props: { kind: 'email' } });

    await submitForm(wrapper);

    expect(dispatch).toHaveBeenCalledWith('campaigns/create', details);
    expect(useAlert).toHaveBeenCalledWith('CAMPAIGN.CHANNEL_CAMPAIGN.CREATE.FORM.API.SUCCESS_MESSAGE');
    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('se a API recusar, NAO fecha (o operador nao perde a mensagem) e mostra o motivo dado pelo backend', async () => {
    const error = new Error('AxiosError');
    error.response = { data: { message: 'Inbox needs its own SMTP' } };
    dispatch.mockRejectedValue(error);
    const wrapper = shallowMount(ChannelCampaignDialog, { props: { kind: 'email' } });

    await submitForm(wrapper);

    expect(wrapper.emitted('close')).toBeUndefined();
    expect(useAlert).toHaveBeenCalledWith('Inbox needs its own SMTP');
  });

  it('sem resposta da API (rede), mostra o texto generico e tambem nao fecha', async () => {
    dispatch.mockRejectedValue(new Error('Network Error'));
    const wrapper = shallowMount(ChannelCampaignDialog, { props: { kind: 'channels' } });

    await submitForm(wrapper);

    expect(wrapper.emitted('close')).toBeUndefined();
    expect(useAlert).toHaveBeenCalledWith('CAMPAIGN.CHANNEL_CAMPAIGN.CREATE.FORM.API.ERROR_MESSAGE');
  });

  it('cancelar fecha', () => {
    const wrapper = shallowMount(ChannelCampaignDialog, { props: { kind: 'email' } });

    wrapper.findComponent(ChannelCampaignForm).vm.$emit('cancel');

    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('o titulo depende da aba', () => {
    const email = shallowMount(ChannelCampaignDialog, { props: { kind: 'email' } });
    const channels = shallowMount(ChannelCampaignDialog, { props: { kind: 'channels' } });

    expect(email.text()).toContain('CREATE.TITLE_EMAIL');
    expect(channels.text()).toContain('CREATE.TITLE_CHANNELS');
  });

  it('repassa a aba para o formulario', () => {
    const wrapper = shallowMount(ChannelCampaignDialog, { props: { kind: 'channels' } });

    expect(wrapper.findComponent(ChannelCampaignForm).props('kind')).toBe('channels');
  });
});
