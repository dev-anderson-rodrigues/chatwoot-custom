<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters } from 'dashboard/composables/store';
import {
  useMessageColors,
  MESSAGE_COLOR_PALETTE,
} from 'dashboard/composables/useMessageColors';

const { t } = useI18n();
const getters = useStoreGetters();

const agents = computed(() => getters['agents/getAgents'].value || []);
const { getColorForAgent, setColorForAgent, clearColorForAgent } =
  useMessageColors();

const agentColor = agentId =>
  getColorForAgent(agentId) || MESSAGE_COLOR_PALETTE[0];
</script>

<template>
  <div class="flex flex-col gap-3 w-full">
    <div>
      <label class="text-n-gray-12 font-medium leading-6 text-sm">
        {{ t('PROFILE_SETTINGS.MESSAGE_COLORS.TITLE') }}
      </label>
      <p class="text-n-gray-11 text-sm">
        {{ t('PROFILE_SETTINGS.MESSAGE_COLORS.DESCRIPTION') }}
      </p>
    </div>

    <div class="flex flex-col gap-2 max-h-64 overflow-y-auto pr-1">
      <div
        v-for="agent in agents"
        :key="agent.id"
        class="flex items-center justify-between gap-3 py-1.5"
      >
        <div class="flex items-center gap-2 min-w-0">
          <span
            class="size-3 rounded-full shrink-0"
            :style="{ background: agentColor(agent.id) }"
          />
          <span class="text-sm text-n-slate-12 truncate">{{ agent.name }}</span>
        </div>
        <div class="flex items-center gap-1 shrink-0">
          <button
            v-for="color in MESSAGE_COLOR_PALETTE"
            :key="color"
            class="size-4 rounded-full border-2 transition-transform hover:scale-110"
            :class="
              agentColor(agent.id) === color
                ? 'border-n-slate-12'
                : 'border-transparent'
            "
            :style="{ background: color }"
            :title="color"
            @click="setColorForAgent(agent.id, color)"
          />
          <button
            v-if="getColorForAgent(agent.id)"
            class="size-4 text-n-slate-9 hover:text-n-slate-12 flex items-center justify-center"
            :title="t('PROFILE_SETTINGS.MESSAGE_COLORS.RESET')"
            @click="clearColorForAgent(agent.id)"
          >
            <span class="i-lucide-x size-3" />
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
