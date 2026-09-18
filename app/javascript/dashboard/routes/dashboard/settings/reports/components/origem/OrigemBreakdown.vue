<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  items: { type: Array, default: () => [] },
});

const { t } = useI18n();

const keyLabel = key => t(`REPORT.ORIGEM.ORIGIN.KEY.${key.toUpperCase()}`);
const kindLabel = kind => t(`REPORT.ORIGEM.ORIGIN.KIND.${kind.toUpperCase()}`);
const formatCount = value => Number(value).toLocaleString();
</script>

<template>
  <section class="flex flex-col gap-1">
    <h3 class="m-0 text-sm font-medium text-n-slate-12">
      {{ t('REPORT.ORIGEM.ORIGIN.TITLE') }}
    </h3>

    <p v-if="!items.length" class="m-0 text-sm text-n-slate-11">
      {{ t('REPORT.ORIGEM.ORIGIN.EMPTY') }}
    </p>

    <div v-else class="flex flex-col gap-3 mt-2">
      <div v-for="item in items" :key="item.key" class="flex flex-col gap-1">
        <div class="flex items-center justify-between gap-2">
          <div class="flex items-center gap-2 min-w-0">
            <span class="text-sm font-medium truncate text-n-slate-12">
              {{ keyLabel(item.key) }}
            </span>
            <span
              class="text-xs px-1.5 py-0.5 rounded shrink-0 bg-n-alpha-2 text-n-slate-10"
            >
              {{ kindLabel(item.kind) }}
            </span>
          </div>
          <div class="flex items-center gap-3 shrink-0">
            <span class="text-sm font-bold text-n-slate-12">{{
              formatCount(item.count)
            }}</span>
            <span class="w-10 text-xs text-right text-n-slate-10"
              >{{ item.pct }}%</span
            >
          </div>
        </div>
        <div class="w-full h-2 overflow-hidden rounded-full bg-n-alpha-2">
          <div
            class="h-full transition-all duration-500 rounded-full bg-n-amber-9"
            :style="{ width: `${item.pct}%` }"
          />
        </div>
      </div>
    </div>
  </section>
</template>
