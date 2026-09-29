<script setup>
defineProps({
  label: { type: String, required: true },
});
</script>

<template>
  <li class="flex items-center gap-3 my-2 list-none select-none">
    <span class="flex-1 h-px bg-n-strong" />
    <span class="text-[11px] font-medium text-n-slate-10 px-1">{{ label }}</span>
    <span class="flex-1 h-px bg-n-strong" />
  </li>
</template>
