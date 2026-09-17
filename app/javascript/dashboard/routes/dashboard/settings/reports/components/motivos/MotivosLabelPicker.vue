<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  // Etiquetas da conta, no formato do store (`title` e `color`).
  availableLabels: { type: Array, default: () => [] },
  selected: { type: Array, default: () => [] },
});

const emit = defineEmits(['update']);

const { t } = useI18n();

const isSelected = title => props.selected.includes(title);

// Emite a lista inteira, nao o item alternado: o composable trata `labels` como
// um valor so (troca dispara uma busca), e devolver o array pronto evita que a
// tela precise reconstruir estado.
const toggle = title => {
  const next = isSelected(title)
    ? props.selected.filter(item => item !== title)
    : [...props.selected, title];

  emit('update', next);
};

const selectAll = () =>
  emit(
    'update',
    props.availableLabels.map(label => label.title)
  );

const clear = () => emit('update', []);

const hasLabels = computed(() => props.availableLabels.length > 0);
</script>

<template>
  <div
    role="group"
    :aria-label="t('REPORT.MOTIVOS.LABELS.LABEL')"
    class="flex flex-col gap-2"
  >
    <div class="flex items-center gap-2">
      <span class="text-sm text-n-slate-11">
        {{ t('REPORT.MOTIVOS.LABELS.LABEL') }}
      </span>
      <Button
        v-if="hasLabels"
        :label="t('REPORT.MOTIVOS.LABELS.SELECT_ALL')"
        variant="link"
        color="slate"
        size="sm"
        @click="selectAll"
      />
      <Button
        v-if="selected.length"
        :label="t('REPORT.MOTIVOS.LABELS.CLEAR')"
        variant="link"
        color="slate"
        size="sm"
        @click="clear"
      />
    </div>

    <div v-if="hasLabels" class="flex flex-wrap items-center gap-1.5">
      <button
        v-for="label in availableLabels"
        :key="label.title"
        type="button"
        :aria-pressed="isSelected(label.title)"
        class="flex items-center gap-1.5 px-2.5 py-1 text-sm transition-colors border rounded-full outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        :class="
          isSelected(label.title)
            ? 'border-n-brand bg-n-alpha-2 text-n-slate-12'
            : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
        "
        @click="toggle(label.title)"
      >
        <span
          class="rounded-full size-2.5 shrink-0"
          :style="{ backgroundColor: label.color }"
          aria-hidden="true"
        />
        {{ label.title }}
      </button>
    </div>

    <p v-else class="m-0 text-xs text-n-slate-10">
      {{ t('REPORT.MOTIVOS.LABELS.NONE_IN_ACCOUNT') }}
    </p>
  </div>
</template>
