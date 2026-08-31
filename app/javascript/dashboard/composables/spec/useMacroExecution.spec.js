import { flushPromises } from '@vue/test-utils';
import { useAlert, useTrack } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useConversationRequiredAttributes } from 'dashboard/composables/useConversationRequiredAttributes';
import {
  useMacroExecution,
  INPUT_FIELDS_GATE,
  ATTRIBUTES_GATE,
} from '../useMacroExecution';

vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables');
vi.mock('dashboard/composables/useConversationRequiredAttributes');
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const CONVERSATION_ID = 42;

const addLabel = { action_name: 'add_label', action_params: ['spam'] };
const resolveConversation = {
  action_name: 'resolve_conversation',
  action_params: [],
};

const macroWith = actions => ({ id: 7, name: 'Test macro', actions });

const dispatch = vi.fn();
const checkMissingAttributes = vi.fn();

const mockConversation = (customAttributes = {}) => {
  useMapGetter.mockImplementation(getter =>
    getter === 'getConversationById'
      ? { value: () => ({ custom_attributes: customAttributes }) }
      : { value: null }
  );
};

describe('useMacroExecution', () => {
  beforeEach(() => {
    dispatch.mockReset().mockResolvedValue(undefined);
    checkMissingAttributes.mockReset().mockReturnValue({
      hasMissing: false,
      missing: [],
    });
    useAlert.mockClear();
    useTrack.mockClear();

    useStore.mockReturnValue({ dispatch });
    useConversationRequiredAttributes.mockReturnValue({
      checkMissingAttributes,
    });
    mockConversation();
  });

  it('runs a macro that cannot resolve the conversation straight away', async () => {
    const { execute } = useMacroExecution();

    const pending = execute(macroWith([addLabel]), CONVERSATION_ID);
    await flushPromises();

    expect(pending).toBeNull();
    expect(checkMissingAttributes).not.toHaveBeenCalled();
    expect(dispatch).toHaveBeenCalledWith('macros/execute', {
      macroId: 7,
      conversationIds: [CONVERSATION_ID],
      inputs: {},
    });
    expect(useAlert).toHaveBeenCalledWith(
      'MACROS.EXECUTE.EXECUTED_SUCCESSFULLY'
    );
  });

  it('runs a resolving macro when no required attributes are missing', async () => {
    const { execute } = useMacroExecution();

    const pending = execute(macroWith([resolveConversation]), CONVERSATION_ID);
    await flushPromises();

    expect(pending).toBeNull();
    expect(checkMissingAttributes).toHaveBeenCalled();
    expect(dispatch).toHaveBeenCalledWith('macros/execute', expect.anything());
  });

  it('holds back a resolving macro and reports the missing attributes', async () => {
    checkMissingAttributes.mockReturnValue({
      hasMissing: true,
      missing: ['priority'],
    });
    mockConversation({ category: 'sales' });

    const { execute } = useMacroExecution();

    const pending = execute(macroWith([resolveConversation]), CONVERSATION_ID);
    await flushPromises();

    expect(pending).toEqual({
      kind: ATTRIBUTES_GATE,
      missing: ['priority'],
      customAttributes: { category: 'sales' },
    });
    expect(dispatch).not.toHaveBeenCalled();
  });

  it.each([['resolved'], [1]])(
    'treats change_status %s as resolving the conversation',
    async status => {
      checkMissingAttributes.mockReturnValue({
        hasMissing: true,
        missing: ['priority'],
      });

      const { execute } = useMacroExecution();
      const macro = macroWith([
        { action_name: 'change_status', action_params: [status] },
      ]);

      expect(execute(macro, CONVERSATION_ID)).not.toBeNull();
      await flushPromises();
      expect(dispatch).not.toHaveBeenCalled();
    }
  );

  it('does not treat change_status open as resolving the conversation', async () => {
    checkMissingAttributes.mockReturnValue({
      hasMissing: true,
      missing: ['priority'],
    });

    const { execute } = useMacroExecution();
    const macro = macroWith([
      { action_name: 'change_status', action_params: ['open'] },
    ]);

    expect(execute(macro, CONVERSATION_ID)).toBeNull();
    await flushPromises();
    expect(dispatch).toHaveBeenCalledWith('macros/execute', expect.anything());
  });

  it('saves the submitted attributes before running the pending macro', async () => {
    checkMissingAttributes.mockReturnValue({
      hasMissing: true,
      missing: ['priority'],
    });
    mockConversation({ category: 'sales' });

    const { execute, submitPendingAttributes } = useMacroExecution();
    execute(macroWith([resolveConversation]), CONVERSATION_ID);
    await submitPendingAttributes({ attributes: { priority: 'high' } });
    await flushPromises();

    expect(dispatch).toHaveBeenNthCalledWith(1, 'updateCustomAttributes', {
      conversationId: CONVERSATION_ID,
      customAttributes: { category: 'sales', priority: 'high' },
    });
    expect(dispatch).toHaveBeenNthCalledWith(2, 'macros/execute', {
      macroId: 7,
      conversationIds: [CONVERSATION_ID],
      inputs: {},
    });
  });

  it('does not run the macro when saving the attributes fails', async () => {
    checkMissingAttributes.mockReturnValue({
      hasMissing: true,
      missing: ['priority'],
    });
    dispatch.mockRejectedValueOnce(new Error('nope'));

    const { execute, submitPendingAttributes } = useMacroExecution();
    execute(macroWith([resolveConversation]), CONVERSATION_ID);
    await submitPendingAttributes({ attributes: { priority: 'high' } });
    await flushPromises();

    expect(dispatch).toHaveBeenCalledTimes(1);
    expect(useAlert).toHaveBeenCalledWith(
      'CUSTOM_ATTRIBUTES.FORM.UPDATE.ERROR'
    );
  });

  it('still runs the macro when the prompt is dismissed', async () => {
    checkMissingAttributes.mockReturnValue({
      hasMissing: true,
      missing: ['priority'],
    });

    const { execute, dismissPendingAttributes } = useMacroExecution();
    execute(macroWith([resolveConversation]), CONVERSATION_ID);
    dismissPendingAttributes();
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('macros/execute', expect.anything());
    expect(useAlert).toHaveBeenCalledWith(
      'MACROS.EXECUTE.EXECUTED_WITHOUT_RESOLVING'
    );
  });

  it('ignores a dismissal when nothing is pending', async () => {
    const { dismissPendingAttributes } = useMacroExecution();

    dismissPendingAttributes();
    await flushPromises();

    expect(dispatch).not.toHaveBeenCalled();
  });

  it('alerts when the macro fails to run', async () => {
    dispatch.mockRejectedValueOnce(new Error('boom'));

    const { execute, executingMacroId } = useMacroExecution();
    execute(macroWith([addLabel]), CONVERSATION_ID);
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('MACROS.ERROR');
    expect(executingMacroId.value).toBeNull();
  });

  // [FORK] Portao dos campos de entrada. O ponto delicado e a ordem: ele vem
  // antes do de atributos, e preencher os campos pode esbarrar no seguinte.
  describe('portao dos campos de entrada', () => {
    const inputFields = [{ key: 'cpf', label: 'CPF', type: 'cpf' }];
    const macroWithInputs = actions => ({
      ...macroWith(actions),
      input_fields: inputFields,
    });

    it('holds the macro back and reports the fields to ask for', async () => {
      const { execute } = useMacroExecution();

      const pending = execute(macroWithInputs([addLabel]), CONVERSATION_ID);
      await flushPromises();

      expect(pending.kind).toBe(INPUT_FIELDS_GATE);
      expect(pending.fields).toEqual(inputFields);
      expect(dispatch).not.toHaveBeenCalled();
    });

    it('sends the collected inputs to the backend', async () => {
      const { execute, submitInputs } = useMacroExecution();

      execute(macroWithInputs([addLabel]), CONVERSATION_ID);
      const next = submitInputs({ cpf: '11144477735' });
      await flushPromises();

      expect(next).toBeNull();
      expect(dispatch).toHaveBeenCalledWith('macros/execute', {
        macroId: 7,
        conversationIds: [CONVERSATION_ID],
        inputs: { cpf: '11144477735' },
      });
    });

    // O caso que motivou juntar os dois portoes num fluxo so: preencher os
    // campos nao executa a macro se ela ainda esbarrar nos atributos.
    it('falls through to the attributes gate after the inputs are filled', async () => {
      checkMissingAttributes.mockReturnValue({
        hasMissing: true,
        missing: ['priority'],
      });
      mockConversation({ category: 'sales' });

      const { execute, submitInputs } = useMacroExecution();

      execute(macroWithInputs([resolveConversation]), CONVERSATION_ID);
      const next = submitInputs({ cpf: '11144477735' });
      await flushPromises();

      expect(next).toEqual({
        kind: ATTRIBUTES_GATE,
        missing: ['priority'],
        customAttributes: { category: 'sales' },
      });
      expect(dispatch).not.toHaveBeenCalled();
    });

    it('keeps the inputs through the attributes gate', async () => {
      checkMissingAttributes.mockReturnValue({
        hasMissing: true,
        missing: ['priority'],
      });

      const { execute, submitInputs, submitPendingAttributes } =
        useMacroExecution();

      execute(macroWithInputs([resolveConversation]), CONVERSATION_ID);
      submitInputs({ cpf: '11144477735' });
      await submitPendingAttributes({ attributes: { priority: 'high' } });
      await flushPromises();

      expect(dispatch).toHaveBeenNthCalledWith(2, 'macros/execute', {
        macroId: 7,
        conversationIds: [CONVERSATION_ID],
        inputs: { cpf: '11144477735' },
      });
    });

    // Diferente do modal de atributos, que segue sem resolver: sem os valores a
    // macro nao tem o que substituir.
    it('aborts the execution when the agent dismisses the form', async () => {
      const { execute, cancelInputs, submitInputs } = useMacroExecution();

      execute(macroWithInputs([addLabel]), CONVERSATION_ID);
      cancelInputs();
      await flushPromises();

      expect(dispatch).not.toHaveBeenCalled();
      expect(submitInputs({ cpf: '1' })).toBeNull();
    });

    it('skips the gate when the macro has no input fields', async () => {
      const { execute } = useMacroExecution();

      const pending = execute(
        { ...macroWith([addLabel]), input_fields: [] },
        CONVERSATION_ID
      );
      await flushPromises();

      expect(pending).toBeNull();
      expect(dispatch).toHaveBeenCalled();
    });
  });
});
