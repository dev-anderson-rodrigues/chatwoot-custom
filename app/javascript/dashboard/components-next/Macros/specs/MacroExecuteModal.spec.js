import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import MacroExecuteModal from '../MacroExecuteModal.vue';

withFullI18n();

/**
 * Montagem real do modal de pre-execucao. O foco e o contrato com o
 * useMacroExecution: o que sai no `submit`, e quando o `close` deve (ou nao)
 * ser emitido -- confundir os dois derruba o portao seguinte.
 */
const mountModal = () =>
  mount(MacroExecuteModal, {
    attachTo: document.body,
    global: {
      stubs: {
        // O Dialog usa teleport e getters de conta; aqui interessa o conteudo,
        // nao a moldura. O stub mantem o slot e os eventos.
        Dialog: {
          name: 'Dialog',
          template: '<div><slot /></div>',
          methods: {
            open() {},
            close() {
              this.$emit('close');
            },
          },
          emits: ['close', 'confirm'],
        },
      },
    },
  });

const field = (overrides = {}) => ({
  key: 'cpf',
  label: 'CPF do cliente',
  type: 'text',
  required: false,
  placeholder: '',
  default_value: '',
  ...overrides,
});

const macro = { id: 7, name: 'Abrir chamado' };

describe('MacroExecuteModal', () => {
  it('renders one control per field, labelled and linked', async () => {
    const wrapper = mountModal();
    wrapper.vm.open(macro, [field(), field({ key: 'obs', type: 'textarea' })]);
    await wrapper.vm.$nextTick();

    const label = wrapper.find('label[for="macro-input-cpf"]');
    expect(label.text()).toContain('CPF do cliente');
    expect(wrapper.find('#macro-input-cpf').exists()).toBe(true);
    expect(wrapper.find('textarea#macro-input-obs').exists()).toBe(true);
  });

  it('falls back to the key when the field has no label', async () => {
    const wrapper = mountModal();
    wrapper.vm.open(macro, [field({ label: '' })]);
    await wrapper.vm.$nextTick();

    expect(wrapper.find('label[for="macro-input-cpf"]').text()).toContain(
      'cpf'
    );
  });

  it('starts the form on the configured default values', async () => {
    const wrapper = mountModal();
    wrapper.vm.open(macro, [field({ default_value: 'preenchido' })]);
    await wrapper.vm.$nextTick();

    expect(wrapper.find('#macro-input-cpf').element.value).toBe('preenchido');
  });

  it('emits the collected values on confirm', async () => {
    const wrapper = mountModal();
    wrapper.vm.open(macro, [field()]);
    await wrapper.vm.$nextTick();

    await wrapper.find('#macro-input-cpf').setValue('11144477735');
    await wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');

    expect(wrapper.emitted('submit')[0][0]).toEqual({ cpf: '11144477735' });
  });

  // O Dialog emite `close` tambem ao fechar depois do confirm. Se isso vazasse
  // como desistencia, o chamador limparia a execucao pendente que o portao de
  // atributos acabou de guardar.
  it('does not report a dismissal after a successful confirm', async () => {
    const wrapper = mountModal();
    wrapper.vm.open(macro, [field()]);
    await wrapper.vm.$nextTick();

    await wrapper.find('#macro-input-cpf').setValue('x');
    await wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');

    expect(wrapper.emitted('submit')).toHaveLength(1);
    expect(wrapper.emitted('close')).toBeUndefined();
  });

  it('reports a dismissal when the agent closes without confirming', async () => {
    const wrapper = mountModal();
    wrapper.vm.open(macro, [field()]);
    await wrapper.vm.$nextTick();

    await wrapper.findComponent({ name: 'Dialog' }).vm.$emit('close');

    expect(wrapper.emitted('close')).toHaveLength(1);
    expect(wrapper.emitted('submit')).toBeUndefined();
  });

  it('does not submit while a required field is empty', async () => {
    const wrapper = mountModal();
    wrapper.vm.open(macro, [field({ required: true })]);
    await wrapper.vm.$nextTick();

    await wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');

    expect(wrapper.emitted('submit')).toBeUndefined();
  });

  it('renders select fields as a list of their options', async () => {
    const wrapper = mountModal();
    wrapper.vm.open(macro, [
      field({
        key: 'motivo',
        type: 'select',
        options: [{ value: 'cobranca', label: 'Cobrança' }],
      }),
    ]);
    await wrapper.vm.$nextTick();

    expect(wrapper.text()).toContain('Cobrança');
  });

  it('clears the previous macro fields when reopened', async () => {
    const wrapper = mountModal();
    wrapper.vm.open(macro, [field({ default_value: 'antigo' })]);
    await wrapper.vm.$nextTick();

    wrapper.vm.open(macro, [field({ key: 'outro', label: 'Outro' })]);
    await wrapper.vm.$nextTick();

    expect(wrapper.find('#macro-input-cpf').exists()).toBe(false);
    expect(wrapper.find('#macro-input-outro').exists()).toBe(true);
  });
});
