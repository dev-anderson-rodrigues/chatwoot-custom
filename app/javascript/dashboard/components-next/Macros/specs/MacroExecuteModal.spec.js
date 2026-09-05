import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import {
  getActiveCountryCode,
  getActiveDialCode,
} from 'shared/components/PhoneInput/helper';
import MacroExecuteModal from '../MacroExecuteModal.vue';

withFullI18n();

// PhoneNumberInput deriva o DDI padrao do fuso horario do navegador. Por
// padrao fixamos um DDI valido para isolar o que e desta fatia (normalizacao
// do default) do comportamento de fuso do ambiente -- mas pelo menos um teste
// abaixo roda sem este mock, reproduzindo o cenario real do `TZ=UTC` (sem
// mapeamento pra nenhum pais), que e o que expos o achado do useVuelidate
// aninhado do PhoneNumberInput (ver handleConfirm no componente).
vi.mock('shared/components/PhoneInput/helper', () => ({
  getActiveCountryCode: vi.fn(() => 'BR'),
  getActiveDialCode: vi.fn(() => '+55'),
}));

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

  // O asterisco e um <span aria-hidden>, nao um pseudo-elemento CSS -- uma
  // classe arbitraria do Tailwind (content-['*']) escrita com aspas
  // escapadas dentro de :class="{...}" nunca era detectada pelo scanner
  // estatico do JIT, e o asterisco ficava invisivel em runtime mesmo com a
  // classe presente no DOM (confirmado com getComputedStyle(label,
  // '::after').content saindo vazio). Um pseudo-elemento nao e testavel em
  // jsdom (nao ha CSS de verdade aplicado); o <span> e, e e o que este teste
  // trava.
  it('shows a visible asterisk only on required fields', async () => {
    const wrapper = mountModal();
    wrapper.vm.open(macro, [
      field({ required: true }),
      field({ key: 'obs', label: 'Observacao', required: false }),
    ]);
    await wrapper.vm.$nextTick();

    const requiredLabel = wrapper.find('label[for="macro-input-cpf"]');
    const requiredAsterisk = requiredLabel.find('span[aria-hidden="true"]');
    expect(requiredAsterisk.exists()).toBe(true);
    expect(requiredAsterisk.text()).toBe('*');

    const optionalLabel = wrapper.find('label[for="macro-input-obs"]');
    expect(optionalLabel.find('span[aria-hidden="true"]').exists()).toBe(false);
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

  // Fatia 4: mascara e validacao de CPF/CNPJ/telefone. O Input e controlado,
  // entao o que importa e o valor que fica no DOM, nao so o que o helper
  // devolveria isoladamente (isso ja tem spec proprio em brazilianDocuments).
  describe('CPF/CNPJ', () => {
    it('masks a CPF progressively as the agent types', async () => {
      const wrapper = mountModal();
      wrapper.vm.open(macro, [field({ type: 'cpf' })]);
      await wrapper.vm.$nextTick();

      await wrapper.find('#macro-input-cpf').setValue('52998224725');

      expect(wrapper.find('#macro-input-cpf').element.value).toBe(
        '529.982.247-25'
      );
    });

    it('masks a CNPJ progressively as the agent types', async () => {
      const wrapper = mountModal();
      wrapper.vm.open(macro, [field({ key: 'cnpj', type: 'cnpj' })]);
      await wrapper.vm.$nextTick();

      await wrapper.find('#macro-input-cnpj').setValue('11222333000181');

      expect(wrapper.find('#macro-input-cnpj').element.value).toBe(
        '11.222.333/0001-81'
      );
    });

    // O Input e controlado por :model-value. Uma letra digitada no meio do
    // numero e descartada pela mascara, mas se o valor formatado nao mudar o
    // Vue nao repinta o DOM e a letra fica visivel mesmo fora do modelo.
    it('does not leave a mask-discarded character in the DOM', async () => {
      const wrapper = mountModal();
      wrapper.vm.open(macro, [field({ type: 'cpf' })]);
      await wrapper.vm.$nextTick();

      await wrapper.find('#macro-input-cpf').setValue('529a982');

      expect(wrapper.find('#macro-input-cpf').element.value).toBe('529.982');
    });

    it('rejects a CPF with the right length but a wrong check digit', async () => {
      const wrapper = mountModal();
      wrapper.vm.open(macro, [field({ type: 'cpf', required: true })]);
      await wrapper.vm.$nextTick();

      // 52998224724 tem 11 digitos mas o digito verificador esta errado
      // (o valido e 52998224725).
      await wrapper.find('#macro-input-cpf').setValue('52998224724');
      await wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');

      expect(wrapper.emitted('submit')).toBeUndefined();
      expect(wrapper.text()).toContain('Enter a valid CPF.');
    });

    it('rejects a CNPJ with the right length but a wrong check digit', async () => {
      const wrapper = mountModal();
      wrapper.vm.open(macro, [
        field({ key: 'cnpj', type: 'cnpj', required: true }),
      ]);
      await wrapper.vm.$nextTick();

      await wrapper.find('#macro-input-cnpj').setValue('11222333000182');
      await wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');

      expect(wrapper.emitted('submit')).toBeUndefined();
      expect(wrapper.text()).toContain('Enter a valid CNPJ.');
    });

    it('submits the CPF masked, matching the source-parity decision', async () => {
      const wrapper = mountModal();
      wrapper.vm.open(macro, [field({ type: 'cpf' })]);
      await wrapper.vm.$nextTick();

      await wrapper.find('#macro-input-cpf').setValue('52998224725');
      await wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');

      expect(wrapper.emitted('submit')[0][0]).toEqual({
        cpf: '529.982.247-25',
      });
    });
  });

  // Telefone reusa o PhoneNumberInput em vez de uma mascara manual; aqui so
  // interessa a integracao (fiacao de acessibilidade e o bug de default
  // invalido), o componente em si nao e desta fatia.
  describe('phone', () => {
    it('wires the composite control to its label via aria, not a native for', async () => {
      const wrapper = mountModal();
      wrapper.vm.open(macro, [
        field({ key: 'phone', type: 'phone', label: 'Telefone' }),
      ]);
      await wrapper.vm.$nextTick();

      const label = wrapper.find('label#macro-input-phone-label');
      expect(label.exists()).toBe(true);
      expect(label.attributes('for')).toBeUndefined();
      expect(wrapper.find('[role="group"]').attributes('aria-labelledby')).toBe(
        'macro-input-phone-label'
      );
    });

    // Bug real do PhoneNumberInput: parsePhoneNumber("11999999999") sem "+"
    // nao parseia, o campo aparece vazio, mas sem normalizar o default o
    // agente submeteria o valor antigo por baixo do campo em branco.
    it('does not leak an unparseable default phone value into the submit', async () => {
      const wrapper = mountModal();
      wrapper.vm.open(macro, [
        field({ key: 'phone', type: 'phone', default_value: '11999999999' }),
      ]);
      await wrapper.vm.$nextTick();

      await wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');

      expect(wrapper.emitted('submit')[0][0]).toEqual({ phone: '' });
    });

    it('keeps a default value that already parses as a valid E.164 number', async () => {
      const wrapper = mountModal();
      wrapper.vm.open(macro, [
        field({
          key: 'phone',
          type: 'phone',
          default_value: '+5511999999999',
        }),
      ]);
      await wrapper.vm.$nextTick();

      await wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');

      expect(wrapper.emitted('submit')[0][0]).toEqual({
        phone: '+5511999999999',
      });
    });

    // Reproduz o cenario real do `TZ=UTC` (sem mock do DDI): o
    // PhoneNumberInput registra o proprio useVuelidate no coletor deste
    // modal, e o DDI que ele deriva do fuso do navegador nao resolve nada
    // aqui. Antes do fix, handleConfirm usava v$.value.$invalid agregado e
    // isso reprovava o formulario inteiro em silencio -- mesmo com o campo de
    // telefone opcional e intocado. O portao correto olha campo a campo.
    it('submits when an optional, untouched phone field has no resolvable dial code (real TZ=UTC behavior)', async () => {
      getActiveDialCode.mockReturnValueOnce('');
      getActiveCountryCode.mockReturnValueOnce('');

      const wrapper = mountModal();
      wrapper.vm.open(macro, [field({ key: 'phone', type: 'phone' })]);
      await wrapper.vm.$nextTick();

      await wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');

      expect(wrapper.emitted('submit')[0][0]).toEqual({ phone: '' });
    });
  });

  // Fatia 5: lookup dinamico. As opcoes nao vem de busca por texto -- vem de
  // um POST para lookup_url com os valores atuais de depends_on, disparado
  // (debounced) quando esses valores mudam. A lista renderizada pelo
  // ComboBoxDropdown fica no DOM mesmo fechada (v-show), entao clicar direto
  // num <li role="option"> seleciona sem precisar abrir o dropdown.
  describe('lookup', () => {
    const lookupField = (overrides = {}) =>
      field({
        key: 'contrato',
        label: 'Contrato',
        type: 'lookup',
        lookup_url: 'https://api.example.com/lookup',
        depends_on: ['cpf'],
        ...overrides,
      });

    const selectOption = (wrapper, scopeSelector, label) =>
      wrapper
        .find(scopeSelector)
        .findAll('li[role="option"]')
        .find(li => li.text() === label)
        .trigger('click');

    beforeEach(() => {
      vi.useFakeTimers();
      vi.stubGlobal('fetch', vi.fn());
    });

    afterEach(() => {
      vi.useRealTimers();
      vi.unstubAllGlobals();
    });

    it('does not fetch before its dependencies are filled in', async () => {
      const wrapper = mountModal();
      wrapper.vm.open(macro, [
        field({ key: 'cpf', label: 'CPF' }),
        lookupField(),
      ]);
      await wrapper.vm.$nextTick();

      expect(wrapper.text()).toContain('Fill in first: CPF');
      await vi.advanceTimersByTimeAsync(500);
      expect(fetch).not.toHaveBeenCalled();
    });

    it('fetches once the dependency is filled in, debounced', async () => {
      fetch.mockResolvedValue({
        ok: true,
        json: async () => [{ value: '1', label: 'Contrato 001' }],
      });
      const wrapper = mountModal();
      wrapper.vm.open(macro, [
        field({ key: 'cpf', label: 'CPF' }),
        lookupField(),
      ]);
      await wrapper.vm.$nextTick();

      await wrapper.find('#macro-input-cpf').setValue('52998224725');
      expect(fetch).not.toHaveBeenCalled();

      await vi.advanceTimersByTimeAsync(500);

      expect(fetch).toHaveBeenCalledWith('https://api.example.com/lookup', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ cpf: '52998224725' }),
      });
      expect(wrapper.text()).toContain('Contrato 001');
    });

    // registros: convencao dos webhooks n8n que a Coraxy ja tem em producao --
    // manter para nao quebrar integracao existente no port.
    it('accepts records wrapped in a registros envelope', async () => {
      fetch.mockResolvedValue({
        ok: true,
        json: async () => ({
          registros: [{ value: '1', label: 'Contrato 001' }],
        }),
      });
      const wrapper = mountModal();
      wrapper.vm.open(macro, [
        field({ key: 'cpf', label: 'CPF' }),
        lookupField(),
      ]);
      await wrapper.vm.$nextTick();
      await wrapper.find('#macro-input-cpf').setValue('52998224725');
      await vi.advanceTimersByTimeAsync(500);

      expect(wrapper.text()).toContain('Contrato 001');
    });

    it('maps value_key/label_key, falling back to value/label when unset', async () => {
      fetch.mockResolvedValue({
        ok: true,
        json: async () => [{ codigo: 'X1', nome: 'Nome X1' }],
      });
      const wrapper = mountModal();
      wrapper.vm.open(macro, [
        field({ key: 'cpf', label: 'CPF' }),
        lookupField({ value_key: 'codigo', label_key: 'nome' }),
      ]);
      await wrapper.vm.$nextTick();
      await wrapper.find('#macro-input-cpf').setValue('52998224725');
      await vi.advanceTimersByTimeAsync(500);

      expect(wrapper.text()).toContain('Nome X1');
    });

    it('shows a translated error, not the raw fetch failure, when the lookup fails', async () => {
      fetch.mockResolvedValue({ ok: false, status: 500 });
      const wrapper = mountModal();
      wrapper.vm.open(macro, [
        field({ key: 'cpf', label: 'CPF' }),
        lookupField(),
      ]);
      await wrapper.vm.$nextTick();
      await wrapper.find('#macro-input-cpf').setValue('52998224725');
      await vi.advanceTimersByTimeAsync(500);

      expect(wrapper.text()).toContain(
        'Could not load the options. Try again.'
      );
      expect(wrapper.text()).not.toContain('HTTP 500');
    });

    // Achado do backend-engineering: `values[key] = array.filter(...)`
    // sempre cria uma referencia nova, mesmo quando nada e removido. Como
    // `values` e reactive e o watch compara referencia (nao conteudo), isso
    // reagendava o mesmo fetch pra sempre -- um POST pra lookup_url a cada
    // ~500ms, indefinidamente, enquanto o modal ficasse aberto. Sem o guard
    // de tamanho em useMacroLookup.js este teste falha (fetch chamado mais
    // de uma vez apos varios ciclos de debounce sem nenhuma mudanca real).
    it('does not loop forever refetching a multi lookup once nothing changes', async () => {
      fetch.mockResolvedValue({
        ok: true,
        json: async () => [{ value: '1', label: 'Contrato 001' }],
      });
      const wrapper = mountModal();
      wrapper.vm.open(macro, [
        field({ key: 'cpf', label: 'CPF' }),
        lookupField({ multi: true }),
      ]);
      await wrapper.vm.$nextTick();
      await wrapper.find('#macro-input-cpf').setValue('52998224725');

      await vi.advanceTimersByTimeAsync(500);
      await vi.advanceTimersByTimeAsync(500);
      await vi.advanceTimersByTimeAsync(500);
      await vi.advanceTimersByTimeAsync(500);

      expect(fetch).toHaveBeenCalledTimes(1);
    });

    // Achado do backend-engineering: open() limpava os timers agendados, mas
    // nao invalidava um fetch ja em voo. Duas macros que reusem a mesma
    // chave de campo (plausivel -- "contrato", "cliente_id") deixariam a
    // resposta atrasada da macro antiga escrever no estado da macro nova.
    it('discards a stale lookup response after the modal reopens for a different macro', async () => {
      let resolveFirstFetch;
      fetch.mockImplementationOnce(
        () =>
          new Promise(resolve => {
            resolveFirstFetch = resolve;
          })
      );

      const wrapper = mountModal();
      wrapper.vm.open(macro, [
        field({ key: 'cpf', label: 'CPF' }),
        lookupField(),
      ]);
      await wrapper.vm.$nextTick();
      await wrapper.find('#macro-input-cpf').setValue('52998224725');
      await vi.advanceTimersByTimeAsync(500);

      // Reabre para uma macro diferente com um campo de mesma chave
      // ("contrato") antes da resposta original chegar.
      wrapper.vm.open(macro, [
        field({ key: 'cpf', label: 'CPF' }),
        lookupField({ label: 'Contrato (outra macro)' }),
      ]);
      await wrapper.vm.$nextTick();

      resolveFirstFetch({
        ok: true,
        json: async () => [{ value: 'stale', label: 'Nao deveria aparecer' }],
      });
      await vi.advanceTimersByTimeAsync(0);
      await wrapper.vm.$nextTick();

      expect(wrapper.text()).not.toContain('Nao deveria aparecer');
      expect(wrapper.text()).toContain('Contrato (outra macro)');
    });

    it('submits the option the agent picked from the fetched list', async () => {
      fetch.mockResolvedValue({
        ok: true,
        json: async () => [{ value: '1', label: 'Contrato 001' }],
      });
      const wrapper = mountModal();
      wrapper.vm.open(macro, [
        field({ key: 'cpf', label: 'CPF' }),
        lookupField(),
      ]);
      await wrapper.vm.$nextTick();
      await wrapper.find('#macro-input-cpf').setValue('52998224725');
      await vi.advanceTimersByTimeAsync(500);
      await wrapper.vm.$nextTick();

      await selectOption(wrapper, '#macro-input-contrato', 'Contrato 001');
      await wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');

      expect(wrapper.emitted('submit')[0][0]).toMatchObject({ contrato: '1' });
    });

    it('does not submit a required lookup left unselected', async () => {
      fetch.mockResolvedValue({
        ok: true,
        json: async () => [{ value: '1', label: 'Contrato 001' }],
      });
      const wrapper = mountModal();
      wrapper.vm.open(macro, [
        field({ key: 'cpf', label: 'CPF' }),
        lookupField({ required: true }),
      ]);
      await wrapper.vm.$nextTick();
      await wrapper.find('#macro-input-cpf').setValue('52998224725');
      await vi.advanceTimersByTimeAsync(500);
      await wrapper.vm.$nextTick();

      await wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');

      expect(wrapper.emitted('submit')).toBeUndefined();
    });

    // Trocar o CPF refaz a busca; o contrato escolhido para o CPF anterior
    // pode nao existir mais na lista nova -- mante-lo selecionado mandaria um
    // valor que o agente nunca escolheu para este cliente.
    it('clears a stale selection once its dependency changes and the refetch drops it', async () => {
      fetch.mockResolvedValueOnce({
        ok: true,
        json: async () => [{ value: '1', label: 'Contrato 001' }],
      });
      const wrapper = mountModal();
      wrapper.vm.open(macro, [
        field({ key: 'cpf', label: 'CPF' }),
        lookupField(),
      ]);
      await wrapper.vm.$nextTick();
      await wrapper.find('#macro-input-cpf').setValue('52998224725');
      await vi.advanceTimersByTimeAsync(500);
      await wrapper.vm.$nextTick();
      await selectOption(wrapper, '#macro-input-contrato', 'Contrato 001');

      fetch.mockResolvedValueOnce({
        ok: true,
        json: async () => [{ value: '2', label: 'Contrato 002' }],
      });
      await wrapper.find('#macro-input-cpf').setValue('11144477735');
      await vi.advanceTimersByTimeAsync(500);
      await wrapper.vm.$nextTick();

      await wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');

      expect(wrapper.emitted('submit')[0][0]).toMatchObject({ contrato: '' });
    });

    describe('multi', () => {
      it('wires the control to its label via aria, not a native for', async () => {
        const wrapper = mountModal();
        wrapper.vm.open(macro, [
          field({ key: 'cpf', label: 'CPF' }),
          lookupField({ multi: true }),
        ]);
        await wrapper.vm.$nextTick();

        const label = wrapper.find('label#macro-input-contrato-label');
        expect(label.exists()).toBe(true);
        expect(label.attributes('for')).toBeUndefined();
        expect(
          wrapper
            .find('[aria-labelledby="macro-input-contrato-label"]')
            .exists()
        ).toBe(true);
      });

      it('accumulates every option the agent picks into an array', async () => {
        fetch.mockResolvedValue({
          ok: true,
          json: async () => [
            { value: '1', label: 'Contrato 001' },
            { value: '2', label: 'Contrato 002' },
          ],
        });
        const wrapper = mountModal();
        wrapper.vm.open(macro, [
          field({ key: 'cpf', label: 'CPF' }),
          lookupField({ multi: true }),
        ]);
        await wrapper.vm.$nextTick();
        await wrapper.find('#macro-input-cpf').setValue('52998224725');
        await vi.advanceTimersByTimeAsync(500);
        await wrapper.vm.$nextTick();

        const scope = '[aria-labelledby="macro-input-contrato-label"]';
        await selectOption(wrapper, scope, 'Contrato 001');
        await selectOption(wrapper, scope, 'Contrato 002');
        await wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');

        expect(wrapper.emitted('submit')[0][0]).toMatchObject({
          contrato: ['1', '2'],
        });
      });
    });
  });
});
