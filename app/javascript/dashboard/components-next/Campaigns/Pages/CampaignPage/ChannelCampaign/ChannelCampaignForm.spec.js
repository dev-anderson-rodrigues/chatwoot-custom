import { ref } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import ChannelCampaignForm from './ChannelCampaignForm.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: name =>
    ({
      'campaigns/getUIFlags': ref({ isCreating: false }),
      'labels/getLabels': ref([{ id: 7, title: 'inadimplente' }]),
      'inboxes/getInboxes': ref([
        { id: 1, name: 'Cobrança', channel_type: 'Channel::Email' },
        { id: 2, name: 'Bot', channel_type: 'Channel::Telegram' },
        { id: 3, name: 'Site', channel_type: 'Channel::WebWidget' },
        { id: 4, name: 'Zap', channel_type: 'Channel::Whatsapp' },
        { id: 5, name: 'Sms', channel_type: 'Channel::Sms' },
      ]),
    })[name],
}));

const mountForm = kind =>
  shallowMount(ChannelCampaignForm, { props: { kind } });

const fill = async (wrapper, { subject, inboxId, scheduledAt = '2030-01-01T10:00' }) => {
  const inputs = wrapper.findAllComponents(Input);
  const isEmail = inputs.length === 3;

  inputs[0].vm.$emit('update:modelValue', 'Cobrança de setembro');
  if (isEmail) inputs[1].vm.$emit('update:modelValue', subject);
  inputs[inputs.length - 1].vm.$emit('update:modelValue', scheduledAt);
  wrapper
    .findComponent(TextArea)
    .vm.$emit('update:modelValue', 'Olá {{ contact.name }}');
  wrapper.findComponent(ComboBox).vm.$emit('update:modelValue', inboxId);
  wrapper
    .findComponent(TagMultiSelectComboBox)
    .vm.$emit('update:modelValue', [7]);
  await flushPromises();
};

const submit = async wrapper => {
  await wrapper.find('form').trigger('submit');
  await flushPromises();
};

describe('ChannelCampaignForm', () => {
  describe('aba E-mail', () => {
    it('lista so as caixas de e-mail', () => {
      const wrapper = mountForm('email');

      expect(wrapper.findComponent(ComboBox).props('options')).toEqual([
        { value: 1, label: 'Cobrança' },
      ]);
    });

    it('pede o assunto', () => {
      // titulo, assunto e horario
      expect(mountForm('email').findAllComponents(Input)).toHaveLength(3);
    });

    it('envia o assunto em template_params, com o resto da campanha', async () => {
      const wrapper = mountForm('email');
      await fill(wrapper, { subject: 'Sua fatura vence', inboxId: 1 });

      await submit(wrapper);

      const [payload] = wrapper.emitted('submit')[0];
      expect(payload).toEqual({
        title: 'Cobrança de setembro',
        message: 'Olá {{ contact.name }}',
        inbox_id: 1,
        scheduled_at: expect.any(String),
        audience: [{ id: 7, type: 'Label' }],
        template_params: { subject: 'Sua fatura vence' },
      });
    });

    it('nao envia sem o assunto (o backend tambem recusa)', async () => {
      const wrapper = mountForm('email');
      await fill(wrapper, { subject: '', inboxId: 1 });

      await submit(wrapper);

      expect(wrapper.emitted('submit')).toBeUndefined();
    });

    it('nao mostra o aviso de limites dos outros canais', () => {
      expect(mountForm('email').text()).not.toContain('CHANNELS_NOTICE');
    });
  });

  describe('aba Outros canais', () => {
    it('lista so as caixas dos outros canais, com o nome do canal', () => {
      const wrapper = mountForm('channels');

      expect(wrapper.findComponent(ComboBox).props('options')).toEqual([
        { value: 2, label: 'Bot · Telegram' },
      ]);
    });

    it('nao pede assunto', () => {
      // titulo e horario
      expect(mountForm('channels').findAllComponents(Input)).toHaveLength(2);
    });

    it('avisa que so alcanca quem ja escreveu para a caixa', () => {
      expect(mountForm('channels').text()).toContain('CHANNELS_NOTICE');
    });

    it('envia sem template_params', async () => {
      const wrapper = mountForm('channels');
      await fill(wrapper, { inboxId: 2 });

      await submit(wrapper);

      const [payload] = wrapper.emitted('submit')[0];
      expect(payload).toMatchObject({ inbox_id: 2 });
      expect(payload).not.toHaveProperty('template_params');
    });
  });

  describe('horario agendado', () => {
    it('nao aceita data no passado (o agendador so pega os ultimos dias e o operador nao esperaria o envio na hora)', async () => {
      const wrapper = mountForm('email');
      await fill(wrapper, { subject: 'Assunto', inboxId: 1, scheduledAt: '2020-01-01T10:00' });

      await submit(wrapper);

      expect(wrapper.emitted('submit')).toBeUndefined();
      const inputs = wrapper.findAllComponents(Input);
      expect(inputs[inputs.length - 1].props('message')).toContain('SCHEDULED_AT.PAST_ERROR');
    });

    it('sem horario, o erro e o de obrigatorio (nao o de passado)', async () => {
      const wrapper = mountForm('email');
      await fill(wrapper, { subject: 'Assunto', inboxId: 1, scheduledAt: '' });

      await submit(wrapper);

      const inputs = wrapper.findAllComponents(Input);
      expect(inputs[inputs.length - 1].props('message')).toContain('SCHEDULED_AT.ERROR');
    });

    it('mostra em que fuso o horario vale', () => {
      const inputs = mountForm('email').findAllComponents(Input);

      expect(inputs[inputs.length - 1].props('message')).toContain('SCHEDULED_AT.HINT');
    });
  });

  it('o formulario so emite submit: quem cria e decide fechar e o dialogo (se a API recusar, o texto nao se perde)', async () => {
    const wrapper = mountForm('channels');
    await fill(wrapper, { inboxId: 2 });

    await submit(wrapper);

    expect(wrapper.emitted('submit')).toHaveLength(1);
    expect(wrapper.emitted('cancel')).toBeUndefined();
    expect(wrapper.findComponent(TextArea).props('modelValue')).toBe('Olá {{ contact.name }}');
  });

  it('as chaves de Liquid do exemplo nao vao no template (fechariam a interpolacao do Vue)', () => {
    // A dica de variaveis e montada no script; se as chaves fossem escritas no template,
    // o build do Vue quebraria antes de chegar aqui. O teste garante que a dica renderiza.
    expect(mountForm('email').text()).toContain('MESSAGE.HINT');
  });
});
