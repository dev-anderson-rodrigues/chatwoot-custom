<script setup>
import { useI18n } from 'vue-i18n';
import { useDashboardApp } from 'dashboard/composables/useDashboardApp';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  appId: {
    type: [String, Number],
    required: true,
  },
});

const { t } = useI18n();

const { app, frames, isLoading } = useDashboardApp(() => props.appId);
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden">
    <div v-if="isLoading" class="flex items-center justify-center h-full">
      <Spinner />
    </div>

    <template v-else-if="frames.length">
      <iframe
        v-for="frame in frames"
        :key="frame.url"
        :src="frame.url"
        :title="app.title"
        class="flex-1 w-full border-0"
      />
    </template>

    <p
      v-else
      class="flex items-center justify-center h-full m-0 text-sm text-n-slate-11"
    >
      {{ t('DASHBOARD_APPS.NOT_FOUND') }}
    </p>
  </div>
</template>
