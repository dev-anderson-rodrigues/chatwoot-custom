import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert, useTrack } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useConversationRequiredAttributes } from 'dashboard/composables/useConversationRequiredAttributes';
import { CONVERSATION_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';

// change_status is not offered by the macro builder, but the API accepts it and
// it resolves the conversation just like resolve_conversation does. Its param is
// stored as raw JSON, so the status can be the enum name or its integer value.
const RESOLVED_STATUSES = ['resolved', 1];

const resolvesConversation = macro =>
  macro.actions.some(
    ({ action_name: name, action_params: params }) =>
      name === 'resolve_conversation' ||
      (name === 'change_status' && RESOLVED_STATUSES.includes(params?.[0]))
  );

// [FORK] Portoes de pre-execucao, na ordem em que o agente os encontra.
export const INPUT_FIELDS_GATE = 'input_fields';
export const ATTRIBUTES_GATE = 'attributes';

const inputFieldsOf = macro => macro.input_fields || [];

/**
 * Runs a macro against a conversation, holding it back until everything it needs
 * is filled in.
 *
 * [FORK] Sao dois portoes, nao um. Primeiro os `input_fields` da macro (o que o
 * agente digita), depois os atributos obrigatorios da conversa (exigidos quando
 * a macro resolve). Eles vivem aqui, e nao no componente que chama, porque o
 * segundo so pode ser avaliado depois que o primeiro passa -- espalhar isso em
 * `if` soltos no chamador faria cada tela reimplementar a ordem.
 *
 * `execute` devolve `null` quando a macro ja foi despachada, ou um descritor
 * `{ kind, ... }` dizendo qual modal abrir. `submitInputs` continua o fluxo e
 * devolve no mesmo formato, porque preencher os campos pode esbarrar no portao
 * seguinte.
 */
export function useMacroExecution() {
  const store = useStore();
  const { t } = useI18n();
  const { checkMissingAttributes } = useConversationRequiredAttributes();

  const conversationById = useMapGetter('getConversationById');

  const executingMacroId = ref(null);
  const pendingExecution = ref(null);

  const customAttributesFor = conversationId =>
    conversationById.value(conversationId)?.custom_attributes || {};

  const runMacro = async (
    { macro, conversationId, inputs = {} },
    skippedResolve = false
  ) => {
    try {
      executingMacroId.value = macro.id;
      await store.dispatch('macros/execute', {
        macroId: macro.id,
        conversationIds: [conversationId],
        inputs,
      });
      useTrack(CONVERSATION_EVENTS.EXECUTED_A_MACRO);
      useAlert(
        skippedResolve
          ? t('MACROS.EXECUTE.EXECUTED_WITHOUT_RESOLVING')
          : t('MACROS.EXECUTE.EXECUTED_SUCCESSFULLY')
      );
    } catch (error) {
      useAlert(t('MACROS.ERROR'));
    } finally {
      executingMacroId.value = null;
    }
  };

  // Segundo portao. Isolado porque duas entradas chegam nele: uma macro sem
  // campos de entrada, e uma que acabou de ter os campos preenchidos.
  const checkRequiredAttributes = execution => {
    if (!resolvesConversation(execution.macro)) {
      runMacro(execution);
      return null;
    }

    const customAttributes = customAttributesFor(execution.conversationId);
    const { hasMissing, missing } = checkMissingAttributes(customAttributes);
    if (!hasMissing) {
      runMacro(execution);
      return null;
    }

    pendingExecution.value = execution;
    return { kind: ATTRIBUTES_GATE, missing, customAttributes };
  };

  const execute = (macro, conversationId) => {
    const execution = { macro, conversationId, inputs: {} };

    const fields = inputFieldsOf(macro);
    if (fields.length) {
      pendingExecution.value = execution;
      return { kind: INPUT_FIELDS_GATE, macro, fields };
    }

    return checkRequiredAttributes(execution);
  };

  // Preencher os campos nao executa a macro: ela ainda pode esbarrar no portao
  // dos atributos, entao o retorno tem o mesmo formato do `execute`.
  const submitInputs = inputs => {
    const execution = pendingExecution.value;
    if (!execution) return null;

    pendingExecution.value = null;
    return checkRequiredAttributes({ ...execution, inputs });
  };

  // Fechar o modal de campos aborta: sem os valores a macro nao tem o que
  // substituir, diferente do modal de atributos, que segue sem resolver.
  const cancelInputs = () => {
    pendingExecution.value = null;
  };

  const submitPendingAttributes = async ({ attributes }) => {
    const execution = pendingExecution.value;
    pendingExecution.value = null;

    try {
      await store.dispatch('updateCustomAttributes', {
        conversationId: execution.conversationId,
        customAttributes: {
          ...customAttributesFor(execution.conversationId),
          ...attributes,
        },
      });
    } catch (error) {
      useAlert(t('CUSTOM_ATTRIBUTES.FORM.UPDATE.ERROR'));
      return;
    }

    runMacro(execution);
  };

  // Dismissing the modal still runs the macro, the backend leaves the
  // conversation unresolved while the required attributes are empty.
  const dismissPendingAttributes = () => {
    if (!pendingExecution.value) return;

    runMacro(pendingExecution.value, true);
    pendingExecution.value = null;
  };

  return {
    executingMacroId,
    execute,
    submitInputs,
    cancelInputs,
    submitPendingAttributes,
    dismissPendingAttributes,
  };
}
