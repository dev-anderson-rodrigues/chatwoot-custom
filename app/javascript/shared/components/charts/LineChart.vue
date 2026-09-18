<script setup>
import { LineChart as VizLineChart } from '@chatwoot/viz';

const props = defineProps({
  data: {
    type: Object,
    required: true,
  },
  ariaLabel: {
    type: String,
    required: true,
  },
  clickable: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['itemClick']);

defineOptions({ inheritAttrs: false });

const handleItemClick = payload => emit('itemClick', payload);
</script>

<template>
  <VizLineChart
    v-bind="$attrs"
    :data="props.data"
    :aria-label="props.ariaLabel"
    :on-item-click="props.clickable ? handleItemClick : undefined"
    class="[--cw-viz-line-label-color:rgb(var(--slate-11))] [--cw-viz-line-axis-color:rgb(var(--slate-4))] [--cw-viz-line-axis-font-size:0.75rem] [--cw-viz-line-value-font-size:0.75rem] [--cw-viz-line-width:0.0625rem] [--cw-viz-line-point-border-width:0.25rem] [--cw-viz-line-tooltip-background:rgb(var(--solid-2))] [--cw-viz-line-tooltip-color:rgb(var(--slate-12))] [--cw-viz-line-tooltip-border-color:rgb(var(--border-strong))] [&_.cw-viz-line__axis-label]:font-[440] [&_.cw-viz-line__axis-label]:tracking-[-0.015rem] [&_.cw-viz-line__value]:font-[440] [&_.cw-viz-line__value]:tracking-[-0.015rem]"
  />
</template>
