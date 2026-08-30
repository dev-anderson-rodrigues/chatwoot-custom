<script>
import Draggable from 'vuedraggable';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
// NextSelect e nao Select: "Select" e nome reservado de elemento HTML e o
// vue/no-reserved-component-names barra o registro na Options API.
import NextSelect from 'dashboard/components-next/select/Select.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import { MACRO_INPUT_FIELD_TYPES } from 'dashboard/helper/validations';

export default {
  components: {
    Draggable,
    NextButton,
    Icon,
    NextSelect,
    Checkbox,
  },
  props: {
    modelValue: {
      type: Array,
      default: () => [],
    },
    // Chaveado por `input_field_<indice>`, no mesmo formato que o MacroForm ja
    // usa para as acoes. Ver validateMacroInputFields.
    errors: {
      type: Object,
      default: () => ({}),
    },
    readOnly: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['update:modelValue'],
  computed: {
    fields() {
      return this.modelValue;
    },
    typeOptions() {
      return MACRO_INPUT_FIELD_TYPES.map(type => ({
        value: type,
        label: this.$t(`MACROS.INPUT_FIELDS.TYPES.${type.toUpperCase()}`),
      }));
    },
  },
  methods: {
    errorsFor(index) {
      return this.errors[`input_field_${index}`] || {};
    },
    errorMessage(index, property) {
      const code = this.errorsFor(index)[property];
      if (!code) return '';

      return this.$t(`MACROS.INPUT_FIELDS.${code}`);
    },
    // Chaves de outros campos, para o seletor de dependencias do lookup. Um
    // campo nao pode depender de si mesmo, nem de campo sem chave definida.
    dependencyOptions(index) {
      return this.fields
        .filter((field, i) => i !== index && field.key)
        .map(field => ({ value: field.key, label: field.label || field.key }));
    },
    addField() {
      if (this.readOnly) return;

      this.$emit('update:modelValue', [
        ...this.fields,
        {
          key: '',
          label: '',
          type: 'text',
          required: false,
          placeholder: '',
          default_value: '',
        },
      ]);
    },
    removeField(index) {
      if (this.readOnly) return;

      this.$emit(
        'update:modelValue',
        this.fields.filter((field, i) => i !== index)
      );
    },
    updateField(index, changes) {
      if (this.readOnly) return;

      this.$emit(
        'update:modelValue',
        this.fields.map((field, i) =>
          i === index ? { ...field, ...changes } : field
        )
      );
    },
    // Trocar de tipo descarta a configuracao que so faz sentido no tipo antigo,
    // senao a macro seria salva com options de um select que virou texto.
    updateType(index, type) {
      const {
        options,
        lookup_url: lookupUrl,
        value_key: valueKey,
        label_key: labelKey,
        multi,
        depends_on: dependsOn,
        ...rest
      } = this.fields[index];

      const changes = { ...rest, type };
      if (type === 'select') changes.options = options || [];
      if (type === 'lookup') {
        changes.lookup_url = lookupUrl || '';
        changes.value_key = valueKey || '';
        changes.label_key = labelKey || '';
        changes.multi = multi || false;
        changes.depends_on = dependsOn || [];
      }

      this.$emit(
        'update:modelValue',
        this.fields.map((field, i) => (i === index ? changes : field))
      );
    },
    addOption(index) {
      const options = [...(this.fields[index].options || [])];
      options.push({ value: '', label: '' });
      this.updateField(index, { options });
    },
    updateOption(index, optionIndex, changes) {
      const options = this.fields[index].options.map((option, i) =>
        i === optionIndex ? { ...option, ...changes } : option
      );
      this.updateField(index, { options });
    },
    removeOption(index, optionIndex) {
      this.updateField(index, {
        options: this.fields[index].options.filter(
          (option, i) => i !== optionIndex
        ),
      });
    },
    toggleDependency(index, key) {
      const current = this.fields[index].depends_on || [];
      const depends_on = current.includes(key)
        ? current.filter(item => item !== key)
        : [...current, key];

      this.updateField(index, { depends_on });
    },
  },
};
</script>

<template>
  <div class="p-4 bg-n-solid-2 border border-n-weak rounded-lg shadow-sm">
    <div class="flex items-start justify-between gap-4">
      <div class="min-w-0">
        <h3 class="m-0 text-heading-3 text-n-slate-12">
          {{ $t('MACROS.INPUT_FIELDS.TITLE') }}
        </h3>
        <p class="mt-1 mb-0 text-n-slate-11 text-body-para">
          {{ $t('MACROS.INPUT_FIELDS.DESCRIPTION') }}
        </p>
      </div>
      <NextButton
        v-if="!readOnly"
        faded
        blue
        sm
        icon="i-lucide-plus"
        :label="$t('MACROS.INPUT_FIELDS.ADD_FIELD')"
        class="flex-shrink-0"
        @click="addField"
      />
    </div>

    <p
      v-if="!fields.length"
      class="mt-4 mb-0 text-n-slate-11 text-body-para text-center py-6"
    >
      {{ $t('MACROS.INPUT_FIELDS.EMPTY') }}
    </p>

    <Draggable
      v-else
      :list="fields"
      animation="200"
      item-key="key"
      ghost-class="opacity-50"
      tag="div"
      class="flex flex-col gap-3 mt-4"
      handle=".macro-input-field__handle"
    >
      <template #item="{ index }">
        <div
          class="p-3 bg-n-solid-1 border border-n-weak rounded-md flex flex-col gap-3"
        >
          <div class="flex items-center gap-2">
            <button
              v-if="!readOnly"
              type="button"
              class="macro-input-field__handle cursor-grab text-n-slate-10 hover:text-n-slate-12"
              :aria-label="$t('MACROS.ORDER_INFO')"
            >
              <Icon icon="i-lucide-grip-vertical" class="size-4" />
            </button>
            <span class="text-label-small text-n-slate-11">
              {{ index + 1 }}
            </span>
            <div class="flex-1" />
            <NextButton
              v-if="!readOnly"
              ghost
              ruby
              xs
              icon="i-lucide-trash-2"
              :aria-label="$t('MACROS.INPUT_FIELDS.REMOVE')"
              @click="removeField(index)"
            />
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-3">
            <woot-input
              :model-value="fields[index].key"
              :label="$t('MACROS.INPUT_FIELDS.KEY')"
              :placeholder="$t('MACROS.INPUT_FIELDS.KEY_PLACEHOLDER')"
              :error="errorMessage(index, 'key')"
              :class="{ error: errorsFor(index).key }"
              :readonly="readOnly"
              @update:model-value="updateField(index, { key: $event })"
            />
            <woot-input
              :model-value="fields[index].label"
              :label="$t('MACROS.INPUT_FIELDS.LABEL')"
              :placeholder="$t('MACROS.INPUT_FIELDS.LABEL_PLACEHOLDER')"
              :error="errorMessage(index, 'label')"
              :class="{ error: errorsFor(index).label }"
              :readonly="readOnly"
              @update:model-value="updateField(index, { label: $event })"
            />
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-3 items-end">
            <div>
              <label
                :for="`macro-input-type-${index}`"
                class="block mb-1 text-sm font-medium leading-[1.8] text-n-slate-12"
              >
                {{ $t('MACROS.INPUT_FIELDS.TYPE') }}
              </label>
              <NextSelect
                :id="`macro-input-type-${index}`"
                :model-value="fields[index].type"
                :options="typeOptions"
                :disabled="readOnly"
                :aria-label="$t('MACROS.INPUT_FIELDS.TYPE')"
                @update:model-value="updateType(index, $event)"
              />
            </div>
            <label class="flex items-center gap-2 h-9">
              <Checkbox
                :model-value="fields[index].required || false"
                :disabled="readOnly"
                @update:model-value="updateField(index, { required: $event })"
              />
              <span class="text-n-slate-12 text-body-para">
                {{ $t('MACROS.INPUT_FIELDS.REQUIRED') }}
              </span>
            </label>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-3">
            <woot-input
              :model-value="fields[index].placeholder"
              :label="$t('MACROS.INPUT_FIELDS.PLACEHOLDER_LABEL')"
              :readonly="readOnly"
              @update:model-value="updateField(index, { placeholder: $event })"
            />
            <woot-input
              :model-value="fields[index].default_value"
              :label="$t('MACROS.INPUT_FIELDS.DEFAULT_VALUE')"
              :readonly="readOnly"
              @update:model-value="
                updateField(index, { default_value: $event })
              "
            />
          </div>

          <!-- select -->
          <div
            v-if="fields[index].type === 'select'"
            class="flex flex-col gap-2"
          >
            <div class="flex items-center justify-between">
              <span class="text-sm font-medium text-n-slate-12">
                {{ $t('MACROS.INPUT_FIELDS.OPTIONS') }}
              </span>
              <NextButton
                v-if="!readOnly"
                ghost
                blue
                xs
                icon="i-lucide-plus"
                :label="$t('MACROS.INPUT_FIELDS.ADD_OPTION')"
                @click="addOption(index)"
              />
            </div>
            <div
              v-for="(option, optionIndex) in fields[index].options || []"
              :key="optionIndex"
              class="flex items-center gap-2"
            >
              <woot-input
                :model-value="option.value"
                :placeholder="$t('MACROS.INPUT_FIELDS.OPTION_VALUE')"
                class="flex-1 mb-0"
                :readonly="readOnly"
                @update:model-value="
                  updateOption(index, optionIndex, { value: $event })
                "
              />
              <woot-input
                :model-value="option.label"
                :placeholder="$t('MACROS.INPUT_FIELDS.OPTION_LABEL')"
                class="flex-1 mb-0"
                :readonly="readOnly"
                @update:model-value="
                  updateOption(index, optionIndex, { label: $event })
                "
              />
              <NextButton
                v-if="!readOnly"
                ghost
                ruby
                xs
                icon="i-lucide-x"
                :aria-label="$t('MACROS.INPUT_FIELDS.REMOVE')"
                @click="removeOption(index, optionIndex)"
              />
            </div>
            <p
              v-if="errorsFor(index).options"
              class="m-0 text-n-ruby-11 text-label-small"
            >
              {{ errorMessage(index, 'options') }}
            </p>
          </div>

          <!-- lookup -->
          <div
            v-if="fields[index].type === 'lookup'"
            class="flex flex-col gap-3"
          >
            <woot-input
              :model-value="fields[index].lookup_url"
              :label="$t('MACROS.INPUT_FIELDS.LOOKUP_URL')"
              placeholder="https://"
              :error="errorMessage(index, 'lookup_url')"
              :class="{ error: errorsFor(index).lookup_url }"
              :readonly="readOnly"
              @update:model-value="updateField(index, { lookup_url: $event })"
            />
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-3">
              <woot-input
                :model-value="fields[index].value_key"
                :label="$t('MACROS.INPUT_FIELDS.LOOKUP_VALUE_KEY')"
                :readonly="readOnly"
                @update:model-value="updateField(index, { value_key: $event })"
              />
              <woot-input
                :model-value="fields[index].label_key"
                :label="$t('MACROS.INPUT_FIELDS.LOOKUP_LABEL_KEY')"
                :readonly="readOnly"
                @update:model-value="updateField(index, { label_key: $event })"
              />
            </div>
            <label class="flex items-center gap-2">
              <Checkbox
                :model-value="fields[index].multi || false"
                :disabled="readOnly"
                @update:model-value="updateField(index, { multi: $event })"
              />
              <span class="text-n-slate-12 text-body-para">
                {{ $t('MACROS.INPUT_FIELDS.LOOKUP_MULTI') }}
              </span>
            </label>

            <fieldset class="m-0 p-0 border-0">
              <legend class="p-0 text-sm font-medium text-n-slate-12">
                {{ $t('MACROS.INPUT_FIELDS.DEPENDS_ON') }}
              </legend>
              <p class="mt-0.5 mb-2 text-n-slate-11 text-label-small">
                {{ $t('MACROS.INPUT_FIELDS.DEPENDS_ON_HINT') }}
              </p>
              <p
                v-if="!dependencyOptions(index).length"
                class="m-0 text-n-slate-11 text-label-small"
              >
                {{ $t('MACROS.INPUT_FIELDS.DEPENDS_ON_EMPTY') }}
              </p>
              <div v-else class="flex flex-wrap gap-3">
                <label
                  v-for="option in dependencyOptions(index)"
                  :key="option.value"
                  class="flex items-center gap-2"
                >
                  <Checkbox
                    :model-value="
                      (fields[index].depends_on || []).includes(option.value)
                    "
                    :disabled="readOnly"
                    @update:model-value="toggleDependency(index, option.value)"
                  />
                  <span class="text-n-slate-12 text-body-para">
                    {{ option.label }}
                  </span>
                </label>
              </div>
              <p
                v-if="errorsFor(index).depends_on"
                class="mt-2 mb-0 text-n-ruby-11 text-label-small"
              >
                {{ errorMessage(index, 'depends_on') }}
              </p>
            </fieldset>
          </div>
        </div>
      </template>
    </Draggable>
  </div>
</template>

<style scoped lang="scss">
:deep(input[type='text']) {
  @apply mb-0;
}

:deep(.error) {
  .message {
    @apply mb-0;
  }
}
</style>
