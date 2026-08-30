export const ATTRIBUTE_KEY_REQUIRED = 'ATTRIBUTE_KEY_REQUIRED';
export const FILTER_OPERATOR_REQUIRED = 'FILTER_OPERATOR_REQUIRED';
export const VALUE_REQUIRED = 'VALUE_REQUIRED';
export const VALUE_MUST_BE_BETWEEN_1_AND_998 =
  'VALUE_MUST_BE_BETWEEN_1_AND_998';
export const ACTION_PARAMETERS_REQUIRED = 'ACTION_PARAMETERS_REQUIRED';
export const ATLEAST_ONE_CONDITION_REQUIRED = 'ATLEAST_ONE_CONDITION_REQUIRED';
export const ATLEAST_ONE_ACTION_REQUIRED = 'ATLEAST_ONE_ACTION_REQUIRED';

export const KEY_REQUIRED = 'KEY_REQUIRED';
export const KEY_INVALID = 'KEY_INVALID';
export const KEY_DUPLICATED = 'KEY_DUPLICATED';
export const LABEL_REQUIRED = 'LABEL_REQUIRED';
export const OPTIONS_REQUIRED = 'OPTIONS_REQUIRED';
export const LOOKUP_URL_REQUIRED = 'LOOKUP_URL_REQUIRED';
export const LOOKUP_URL_INVALID = 'LOOKUP_URL_INVALID';
export const DEPENDS_ON_REQUIRED = 'DEPENDS_ON_REQUIRED';

export const MACRO_INPUT_FIELD_TYPES = [
  'text',
  'textarea',
  'number',
  'email',
  'date',
  'phone',
  'cpf',
  'cnpj',
  'select',
  'lookup',
];

export const MACRO_INPUT_FIELD_KEY_REGEX = /^[a-z][a-z0-9_]*$/;

const isEmptyValue = value => {
  if (!value) {
    return true;
  }

  if (Array.isArray(value)) {
    return !value.length;
  }

  // We can safely check the type here as both the null value
  // and the array is ruled out earlier.
  if (typeof value === 'object') {
    return !Object.keys(value).length;
  }

  return false;
};
// ------------------------------------------------------------------
// ------------------------ Filter Validation -----------------------
// ------------------------------------------------------------------

/**
 * Validates a single filter for conversations or contacts.
 *
 * @param {Object} filter - The filter object to validate.
 * @param {string} filter.attribute_key - The key of the attribute to filter on.
 * @param {string} filter.filter_operator - The operator to use for filtering.
 * @param {string|number|Array} [filter.values] - The value(s) to filter by (required for most operators).
 *
 * @returns {string|null} An error message if validation fails, or null if validation passes.
 */
export const validateSingleFilter = filter => {
  if (!filter.attribute_key) {
    return ATTRIBUTE_KEY_REQUIRED;
  }

  if (!filter.filter_operator) {
    return FILTER_OPERATOR_REQUIRED;
  }

  const operatorRequiresValue = !['is_present', 'is_not_present'].includes(
    filter.filter_operator
  );

  if (operatorRequiresValue && isEmptyValue(filter.values)) {
    return VALUE_REQUIRED;
  }

  if (
    filter.filter_operator === 'days_before' &&
    (parseInt(filter.values, 10) <= 0 || parseInt(filter.values, 10) >= 999)
  ) {
    return VALUE_MUST_BE_BETWEEN_1_AND_998;
  }

  return null;
};

// ------------------------------------------------------------------
// ---------------------- Automation Validation ---------------------
// ------------------------------------------------------------------

/**
 * Validates the basic fields of an automation object.
 *
 * @param {Object} automation - The automation object to validate.
 * @returns {Object} An object containing any validation errors.
 */
const validateBasicFields = automation => {
  const errors = {};
  const requiredFields = ['name', 'description', 'event_name'];

  requiredFields.forEach(field => {
    if (!automation[field]) {
      errors[field] = `${
        field.charAt(0).toUpperCase() + field.slice(1)
      } is required`;
    }
  });

  return errors;
};

/**
 * Validates the conditions of an automation object.
 *
 * @param {Array} conditions - The conditions to validate.
 * @returns {Object} An object containing any validation errors.
 */
export const validateConditions = conditions => {
  const errors = {};

  if (!conditions || conditions.length === 0) {
    errors.conditions = ATLEAST_ONE_CONDITION_REQUIRED;
    return errors;
  }

  conditions.forEach((condition, index) => {
    const error = validateSingleFilter(condition);
    if (error) {
      errors[`condition_${index}`] = error;
    }
  });

  return errors;
};

/**
 * Validates a single action of an automation object.
 *
 * @param {Object} action - The action to validate.
 * @returns {string|null} An error message if validation fails, or null if validation passes.
 */
const validateSingleAction = action => {
  const noParamActions = [
    'mute_conversation',
    'snooze_conversation',
    'resolve_conversation',
    'remove_assigned_agent',
    'remove_assigned_team',
    'open_conversation',
    'pending_conversation',
  ];

  if (
    !noParamActions.includes(action.action_name) &&
    (!action.action_params || action.action_params.length === 0)
  ) {
    return ACTION_PARAMETERS_REQUIRED;
  }

  return null;
};

/**
 * Validates the actions of an automation object.
 *
 * @param {Array} actions - The actions to validate.
 * @returns {Object} An object containing any validation errors.
 */
export const validateActions = actions => {
  if (!actions || actions.length === 0) {
    return { actions: ATLEAST_ONE_ACTION_REQUIRED };
  }

  return actions.reduce((errors, action, index) => {
    const error = validateSingleAction(action);
    if (error) {
      errors[`action_${index}`] = error;
    }
    return errors;
  }, {});
};

/**
 * Validates an automation object.
 *
 * @param {Object} automation - The automation object to validate.
 * @param {string} automation.name - The name of the automation.
 * @param {string} automation.description - The description of the automation.
 * @param {string} automation.event_name - The name of the event that triggers the automation.
 * @param {Array} automation.conditions - An array of condition objects for the automation.
 * @param {string} automation.conditions[].filter_operator - The operator for the condition.
 * @param {string|number} [automation.conditions[].values] - The value(s) for the condition.
 * @param {Array} automation.actions - An array of action objects for the automation.
 * @param {string} automation.actions[].action_name - The name of the action.
 * @param {Array} [automation.actions[].action_params] - The parameters for the action.
 *
 * @returns {Object} An object containing any validation errors.
 */
export const validateAutomation = automation => {
  const basicErrors = validateBasicFields(automation);
  const conditionErrors = validateConditions(automation.conditions);
  const actionErrors = validateActions(automation.actions);

  return {
    ...basicErrors,
    ...conditionErrors,
    ...actionErrors,
  };
};

// ------------------------------------------------------------------
// ------------------ Macro Input Fields Validation -----------------
// ------------------------------------------------------------------

/**
 * Espelha a validacao do backend (Macro#input_fields_format) para o agente ver
 * o erro no campo em vez de descobrir no 422. O servidor continua sendo a
 * autoridade -- aqui e so para nao perder o que ja foi digitado.
 *
 * Uma checagem existe la e nao aqui: se o host do lookup_url e publico
 * (Macros::SafeUrl). Isso depende de resolucao de DNS e nao da para fazer no
 * browser.
 *
 * @param {Object} field
 * @param {Set<string>} keysSeen - chaves ja usadas pelos campos anteriores
 * @returns {Object} erros por propriedade, ex.: { key: 'KEY_INVALID' }
 */
const validateSingleInputField = (field, keysSeen) => {
  const errors = {};
  const key = (field.key || '').trim();

  if (!key) {
    errors.key = KEY_REQUIRED;
  } else if (!MACRO_INPUT_FIELD_KEY_REGEX.test(key)) {
    errors.key = KEY_INVALID;
  } else if (keysSeen.has(key)) {
    errors.key = KEY_DUPLICATED;
  }

  if (!(field.label || '').trim()) {
    errors.label = LABEL_REQUIRED;
  }

  if (field.type === 'select' && !field.options?.length) {
    errors.options = OPTIONS_REQUIRED;
  }

  if (field.type === 'lookup') {
    const url = (field.lookup_url || '').trim();

    if (!url) {
      errors.lookup_url = LOOKUP_URL_REQUIRED;
    } else if (!/^https?:\/\/.+/i.test(url)) {
      errors.lookup_url = LOOKUP_URL_INVALID;
    }

    if (!field.depends_on?.length) {
      errors.depends_on = DEPENDS_ON_REQUIRED;
    }
  }

  return errors;
};

/**
 * @param {Array} fields
 * @returns {Object} erros indexados, ex.: { input_field_0: { key: 'KEY_REQUIRED' } }
 */
export const validateMacroInputFields = fields => {
  if (!fields?.length) return {};

  const keysSeen = new Set();

  return fields.reduce((errors, field, index) => {
    const fieldErrors = validateSingleInputField(field, keysSeen);

    // So registra a chave depois de validar, senao o proprio campo se acusaria
    // de duplicado.
    const key = (field.key || '').trim();
    if (key) keysSeen.add(key);

    if (Object.keys(fieldErrors).length) {
      errors[`input_field_${index}`] = fieldErrors;
    }
    return errors;
  }, {});
};
