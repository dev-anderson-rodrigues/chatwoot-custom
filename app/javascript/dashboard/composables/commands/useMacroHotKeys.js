import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useMacroExecution } from 'dashboard/composables/useMacroExecution';
import { useOrderedMacros } from 'dashboard/composables/useOrderedMacros';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { ICON_TOY_BRICK } from 'dashboard/helper/commandbar/icons';
import {
  isAConversationRoute,
  isAInboxViewRoute,
} from 'dashboard/helper/routeHelpers';

export function useMacroHotKeys() {
  const { t } = useI18n();
  const store = useStore();
  const route = useRoute();

  const { orderedMacros } = useOrderedMacros();
  const {
    execute,
    submitInputs,
    cancelInputs,
    submitPendingAttributes,
    dismissPendingAttributes,
  } = useMacroExecution();
  const { isFeatureFlagEnabled } = usePolicy();

  const currentChat = useMapGetter('getSelectedChat');
  // [FORK] Guarda o portao que barrou a execucao -- campos de entrada ou
  // atributos obrigatorios -- para o commandbar abrir o modal certo. Antes so
  // existia o segundo caso, dai o nome anterior (`pendingAttributes`).
  const pendingGate = ref(null);

  const isMacrosAvailable = computed(
    () =>
      isFeatureFlagEnabled(FEATURE_FLAGS.MACROS) &&
      (isAConversationRoute(route.name) || isAInboxViewRoute(route.name))
  );

  watch(
    isMacrosAvailable,
    isActive => {
      if (isActive && !orderedMacros.value.length) store.dispatch('macros/get');
    },
    { immediate: true }
  );

  const macroHotKeys = computed(() => {
    if (!isMacrosAvailable.value || !orderedMacros.value.length) {
      return [];
    }

    const options = orderedMacros.value.map(macro => ({
      id: `macro-${macro.id}`,
      title: macro.name,
      parent: 'execute_a_macro',
      section: t('COMMAND_BAR.SECTIONS.EXECUTE_MACRO'),
      icon: ICON_TOY_BRICK,
      handler: () => {
        pendingGate.value = execute(macro, currentChat.value.id);
      },
    }));

    return [
      {
        id: 'execute_a_macro',
        title: t('COMMAND_BAR.COMMANDS.EXECUTE_A_MACRO'),
        section: t('COMMAND_BAR.SECTIONS.CONVERSATION'),
        icon: ICON_TOY_BRICK,
        children: options.map(option => option.id),
      },
      ...options,
    ];
  });

  // Preencher os campos pode esbarrar no portao seguinte, entao o resultado
  // volta para o mesmo ref e o commandbar reage abrindo o proximo modal.
  const submitMacroInputs = inputs => {
    pendingGate.value = submitInputs(inputs);
  };

  const cancelMacroInputs = () => {
    pendingGate.value = null;
    cancelInputs();
  };

  return {
    macroHotKeys,
    pendingGate,
    submitMacroInputs,
    cancelMacroInputs,
    submitPendingAttributes,
    dismissPendingAttributes,
  };
}
