import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import WootUIKit from 'dashboard/components';
import MacroInputFieldsBuilder from '../MacroInputFieldsBuilder.vue';

withFullI18n();

/**
 * Montagem REAL (mount, nao shallowMount): renderiza Input, Select, Checkbox e
 * Draggable de verdade.
 *
 * O spec irmao cobre a logica com stubs; este existe para pegar o que stub
 * esconde -- prop com nome errado num componente do design system, template
 * quebrado, chave de i18n inexistente. Nao substitui olhar a tela: contraste,
 * espacamento e modo escuro continuam fora do alcance de teste unitario.
 */
const mountComponent = props =>
  mount(MacroInputFieldsBuilder, {
    props: { modelValue: [], ...props },
    global: { plugins: [WootUIKit] },
  });

const field = (overrides = {}) => ({
  key: 'cpf',
  label: 'CPF',
  type: 'text',
  required: false,
  placeholder: '',
  default_value: '',
  ...overrides,
});

describe('MacroInputFieldsBuilder.vue (render real)', () => {
  it('renders the empty state without blowing up', () => {
    const wrapper = mountComponent();

    expect(wrapper.text()).toContain(
      'No fields defined. This macro runs straight away.'
    );
    expect(wrapper.find('button').exists()).toBe(true);
  });

  it('renders a text field with its inputs and the type dropdown', () => {
    const wrapper = mountComponent({ modelValue: [field()] });

    expect(wrapper.findAll('input[type="text"]').length).toBeGreaterThanOrEqual(
      4
    );

    const select = wrapper.find('select');
    expect(select.exists()).toBe(true);
    expect(select.element.value).toBe('text');
    // Os 10 tipos suportados pelo backend.
    expect(select.findAll('option')).toHaveLength(10);
  });

  it('resolves every type label, leaving no raw i18n key on screen', () => {
    const wrapper = mountComponent({ modelValue: [field()] });
    const labels = wrapper
      .find('select')
      .findAll('option')
      .map(o => o.text());

    expect(labels).toContain('Text');
    expect(labels).toContain('Long text');
    expect(labels).toContain('Lookup');
    expect(wrapper.text()).not.toContain('MACROS.');
  });

  it('renders the options editor only for select fields', () => {
    const plain = mountComponent({ modelValue: [field()] });
    expect(plain.text()).not.toContain('Options');

    const withSelect = mountComponent({
      modelValue: [
        field({ type: 'select', options: [{ value: '1', label: 'Um' }] }),
      ],
    });
    expect(withSelect.text()).toContain('Options');
  });

  it('renders the lookup block with the dependency checkboxes', () => {
    const wrapper = mountComponent({
      modelValue: [
        field({ key: 'cpf' }),
        field({
          key: 'contrato',
          label: 'Contrato',
          type: 'lookup',
          lookup_url: '',
          depends_on: [],
        }),
      ],
    });

    expect(wrapper.text()).toContain('Lookup URL');
    expect(wrapper.text()).toContain('Depends on');
    // required do campo 1, required do campo 2, multi, e a dependencia "CPF"
    expect(
      wrapper.findAll('input[type="checkbox"]').length
    ).toBeGreaterThanOrEqual(4);
  });

  it('shows the dependency empty state when there is nothing to depend on', () => {
    const wrapper = mountComponent({
      modelValue: [field({ type: 'lookup', depends_on: [] })],
    });

    expect(wrapper.text()).toContain(
      'Create other fields first to pick dependencies.'
    );
  });

  it('renders the translated validation error next to the field', () => {
    const wrapper = mountComponent({
      modelValue: [field({ key: 'CPF Cliente' })],
      errors: { input_field_0: { key: 'KEY_INVALID' } },
    });

    expect(wrapper.text()).toContain(
      'Use lowercase letters, digits and underscore only.'
    );
  });

  // Os tres testes abaixo cobrem o que costuma quebrar so na tela. Nao
  // substituem olhar renderizado, mas travam o contrato para nao regredir em
  // silencio numa refatoracao de classes.

  it('collapses to a single column before the lg breakpoint', () => {
    const wrapper = mountComponent({ modelValue: [field()] });
    const grid = wrapper.find('[class*="grid-cols-1"]');

    expect(grid.exists()).toBe(true);
    // Duas colunas so a partir do lg: em telas estreitas o par label/chave
    // empilha em vez de espremer.
    expect(grid.classes()).toContain('lg:grid-cols-2');
  });

  it('paints only with design system tokens, so dark mode follows', () => {
    const wrapper = mountComponent({
      modelValue: [field({ type: 'select', options: [] })],
      errors: { input_field_0: { options: 'OPTIONS_REQUIRED' } },
    });
    // Os comentarios saem antes: o Vue os preserva na renderizacao, e um deles
    // cita valores rgb() justamente para explicar por que o token e necessario.
    // A checagem e sobre estilo aplicado, nao sobre prosa.
    const html = wrapper.html().replace(/<!--[\s\S]*?-->/g, '');

    // Cor fixa nao inverte no tema escuro; os tokens n-* invertem.
    expect(html).not.toMatch(/(?:#[0-9a-f]{3,8}\b|rgba?\(|\bhsla?\()/i);
    expect(html).toMatch(/\b(?:text|bg|border)-n-/);
  });

  it('drops the options when the field stops being a select', async () => {
    const wrapper = mountComponent({
      modelValue: [
        field({ type: 'select', options: [{ value: '1', label: 'Um' }] }),
      ],
    });

    await wrapper.find('select').setValue('text');

    const [updated] = wrapper.emitted('update:modelValue').at(-1)[0];
    expect(updated.type).toBe('text');
    // Deixar options para tras faria o backend recusar o macro na validacao.
    expect(updated.options).toBeUndefined();
  });

  it('hides the destructive controls when read only', () => {
    const editable = mountComponent({ modelValue: [field()] });
    const readOnly = mountComponent({ modelValue: [field()], readOnly: true });

    expect(readOnly.findAll('button').length).toBeLessThan(
      editable.findAll('button').length
    );
  });
});
