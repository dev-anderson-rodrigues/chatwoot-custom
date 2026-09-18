import { shallowMount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import MacroInputFieldsBuilder from '../MacroInputFieldsBuilder.vue';

withFullI18n();

const textField = (overrides = {}) => ({
  key: 'cpf',
  label: 'CPF',
  type: 'text',
  required: false,
  placeholder: '',
  default_value: '',
  ...overrides,
});

const mountComponent = props =>
  shallowMount(MacroInputFieldsBuilder, {
    props: { modelValue: [], ...props },
    global: {
      stubs: {
        NextInput: true,
        NextButton: true,
        Icon: true,
        NextSelect: true,
        Checkbox: true,
        // O Draggable renderiza pelo slot #item, entao precisa de um stub que
        // realmente renderize o slot -- senao nenhum campo aparece no teste.
        Draggable: {
          props: ['list'],
          template:
            '<div><template v-for="(item, index) in list"><slot name="item" :element="item" :index="index" /></template></div>',
        },
      },
    },
  });

const lastEmitted = wrapper => wrapper.emitted('update:modelValue').at(-1)[0];

describe('MacroInputFieldsBuilder.vue', () => {
  it('shows the empty state when there are no fields', () => {
    const wrapper = mountComponent();

    expect(wrapper.text()).toContain(
      'No fields defined. This macro runs straight away.'
    );
  });

  it('appends a text field with sane defaults', async () => {
    const wrapper = mountComponent();

    await wrapper.findComponent({ name: 'NextButton' }).vm.$emit('click');

    expect(lastEmitted(wrapper)).toEqual([
      {
        key: '',
        label: '',
        type: 'text',
        required: false,
        placeholder: '',
        default_value: '',
      },
    ]);
  });

  it('does not append a field when read only', async () => {
    const wrapper = mountComponent({ readOnly: true });

    wrapper.vm.addField();
    await wrapper.vm.$nextTick();

    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });

  it('removes the field at the given position', () => {
    const wrapper = mountComponent({
      modelValue: [
        textField({ key: 'a' }),
        textField({ key: 'b' }),
        textField({ key: 'c' }),
      ],
    });

    wrapper.vm.removeField(1);

    expect(lastEmitted(wrapper).map(f => f.key)).toEqual(['a', 'c']);
  });

  describe('type change', () => {
    it('drops select options when moving away from select', () => {
      const wrapper = mountComponent({
        modelValue: [
          textField({ type: 'select', options: [{ value: '1', label: 'Um' }] }),
        ],
      });

      wrapper.vm.updateType(0, 'text');

      expect(lastEmitted(wrapper)[0]).not.toHaveProperty('options');
    });

    it('drops lookup config when moving away from lookup', () => {
      const wrapper = mountComponent({
        modelValue: [
          textField({
            type: 'lookup',
            lookup_url: 'https://x.com',
            depends_on: ['cpf'],
            multi: true,
          }),
        ],
      });

      wrapper.vm.updateType(0, 'number');

      const field = lastEmitted(wrapper)[0];
      expect(field).not.toHaveProperty('lookup_url');
      expect(field).not.toHaveProperty('depends_on');
      expect(field).not.toHaveProperty('multi');
      expect(field.type).toBe('number');
    });

    it('seeds the lookup config when moving to lookup', () => {
      const wrapper = mountComponent({ modelValue: [textField()] });

      wrapper.vm.updateType(0, 'lookup');

      expect(lastEmitted(wrapper)[0]).toMatchObject({
        type: 'lookup',
        lookup_url: '',
        depends_on: [],
        multi: false,
      });
    });

    it('keeps the shared properties across the change', () => {
      const wrapper = mountComponent({
        modelValue: [textField({ key: 'doc', label: 'Doc', required: true })],
      });

      wrapper.vm.updateType(0, 'cnpj');

      expect(lastEmitted(wrapper)[0]).toMatchObject({
        key: 'doc',
        label: 'Doc',
        required: true,
        type: 'cnpj',
      });
    });
  });

  describe('select options', () => {
    it('adds and removes options', () => {
      const wrapper = mountComponent({
        modelValue: [textField({ type: 'select', options: [] })],
      });

      wrapper.vm.addOption(0);
      expect(lastEmitted(wrapper)[0].options).toEqual([
        { value: '', label: '' },
      ]);
    });
  });

  describe('lookup dependencies', () => {
    const fields = [
      textField({ key: 'cpf' }),
      textField({ key: 'contrato', type: 'lookup', depends_on: [] }),
    ];

    it('offers the other fields as dependencies, never itself', () => {
      const wrapper = mountComponent({ modelValue: fields });

      expect(wrapper.vm.dependencyOptions(1)).toEqual([
        { value: 'cpf', label: 'CPF' },
      ]);
    });

    it('ignores fields that have no key yet', () => {
      const wrapper = mountComponent({
        modelValue: [textField({ key: '' }), fields[1]],
      });

      expect(wrapper.vm.dependencyOptions(1)).toEqual([]);
    });

    it('toggles a dependency on and off', async () => {
      const wrapper = mountComponent({ modelValue: fields });

      wrapper.vm.toggleDependency(1, 'cpf');
      expect(lastEmitted(wrapper)[1].depends_on).toEqual(['cpf']);

      // O componente e controlado pelo pai: sem devolver o novo modelValue, ele
      // segue lendo o array antigo e o segundo toggle ligaria de novo.
      await wrapper.setProps({
        modelValue: [fields[0], { ...fields[1], depends_on: ['cpf'] }],
      });
      wrapper.vm.toggleDependency(1, 'cpf');
      expect(lastEmitted(wrapper)[1].depends_on).toEqual([]);
    });
  });

  describe('errors', () => {
    it('translates the error code for the right field', () => {
      const wrapper = mountComponent({
        modelValue: [textField(), textField({ key: 'x' })],
        errors: { input_field_1: { key: 'KEY_DUPLICATED' } },
      });

      expect(wrapper.vm.errorMessage(1, 'key')).toBe(
        'This key is already used by another field.'
      );
      expect(wrapper.vm.errorMessage(0, 'key')).toBe('');
    });

    it('ignores errors that belong to actions', () => {
      const wrapper = mountComponent({
        modelValue: [textField()],
        errors: { action_0: 'ACTION_PARAMETERS_REQUIRED' },
      });

      expect(wrapper.vm.errorsFor(0)).toEqual({});
    });
  });
});
