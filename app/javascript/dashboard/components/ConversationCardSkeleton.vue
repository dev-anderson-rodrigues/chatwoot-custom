<script setup>
defineProps({
  count: { type: Number, default: 6 },
});
</script>

<template>
  <div>
    <div
      v-for="i in count"
      :key="i"
      class="flex items-start px-3 py-3 gap-3 border-b border-n-slate-3"
    >
      <!-- Avatar skeleton -->
      <div class="size-8 rounded-full bg-n-slate-3 animate-pulse shrink-0 mt-1" />
      <!-- Content skeleton -->
      <div class="flex-1 min-w-0 py-0.5 space-y-2">
        <div class="flex justify-between items-center gap-2">
          <div class="h-3.5 rounded bg-n-slate-3 animate-pulse w-32" />
          <div class="h-3 rounded bg-n-slate-3 animate-pulse w-10 shrink-0" />
        </div>
        <div class="h-3 rounded bg-n-slate-3 animate-pulse w-full" />
        <div
          class="h-3 rounded bg-n-slate-3 animate-pulse"
          :style="{ width: `${60 + (i % 3) * 10}%` }"
        />
      </div>
    </div>
  </div>
</template>
